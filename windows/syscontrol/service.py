"""The LAN sync brain, on an asyncio loop: pairing, synced connections, hello, and passing mascots.
It reports to the UI through `emit(kind, data)`; the UI calls in with `call(method, *args)` from its own thread."""
from __future__ import annotations

import asyncio
import logging
import threading
from dataclasses import replace
from typing import Callable

from . import APP_VERSION, network, pairing, protocol
from .store import Peer, Settings, Store

log = logging.getLogger("syscontrol.service")
PAIRING_WINDOW_SECONDS = 120
MAINTENANCE_SECONDS = 5
HANDSHAKE_SECONDS = 15


class Service:
    def __init__(self, store: Store, emit: Callable[[str, object], None]) -> None:
        self.store = store
        self.settings: Settings = store.load()
        self.emit = emit
        self.loop: asyncio.AbstractEventLoop | None = None
        self.bonjour = network.Bonjour(self.settings.device_id, self.settings.name, self._discovered)
        self.discovered: list[network.Discovered] = []
        self.connections: dict[str, network.Connection] = {}
        self.wants_roaming: dict[str, bool] = {}
        self.versions: dict[str, tuple[str | None, str | None]] = {}
        self._dialing: set[str] = set()
        self._sync_server: asyncio.AbstractServer | None = None
        self._pair_server: asyncio.AbstractServer | None = None
        self._pair_closer: asyncio.TimerHandle | None = None
        self._session: pairing.PairingSession | None = None
        self._session_connection: network.Connection | None = None
        self._stopped = asyncio.Event()

    # ---- thread entry points -------------------------------------------------------------------------------

    def run_in_thread(self) -> threading.Thread:
        ready = threading.Event()

        def main() -> None:
            self.loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self.loop)
            self.loop.call_soon(ready.set)
            self.loop.run_until_complete(self.run())

        thread = threading.Thread(target=main, name="lan-sync", daemon=True)
        thread.start()
        ready.wait(5)
        return thread

    def call(self, method: str, *args: object) -> None:
        """Runs a method on the service loop, from any thread."""
        if self.loop:
            self.loop.call_soon_threadsafe(lambda: getattr(self, method)(*args))

    async def run(self) -> None:
        self._stopped = asyncio.Event()
        await self.bonjour.start()
        await self._reconcile()
        self._publish()
        while not self._stopped.is_set():
            try:
                await asyncio.wait_for(self._stopped.wait(), MAINTENANCE_SECONDS)
            except asyncio.TimeoutError:
                self._connect_to_peers()
        for connection in list(self.connections.values()):
            connection.close()
        await self.bonjour.stop()

    def stop(self) -> None:
        self._stopped.set()

    # ---- settings ------------------------------------------------------------------------------------------

    def update(self, changes: dict) -> None:
        previous = self.settings
        self.settings = replace(self.settings, **changes)
        self.store.save(self.settings)
        if previous.roaming != self.settings.roaming:
            for connection in self.connections.values():
                self._send_hello(connection)
        asyncio.ensure_future(self._reconcile())
        self._publish()

    def set_side(self, peer_id: str, side: str | None) -> None:
        self.settings = self.settings.with_side(peer_id, side)
        self.store.save(self.settings)
        self._publish()

    def unpair(self, peer_id: str) -> None:
        connection = self.connections.pop(peer_id, None)
        if connection:
            connection.close()
        self.store.delete_key(peer_id)
        self.settings = self.settings.removing(peer_id)
        self.store.save(self.settings)
        asyncio.ensure_future(self._reconcile())
        self._publish()

    def _publish(self) -> None:
        self.emit("state", {
            "settings": self.settings,
            "connected": sorted(self.connections),
            "versions": dict(self.versions),
            "pairing_open": self._pair_server is not None,
            "nearby": [found for found in self.discovered
                       if found.is_pairing and not self.settings.peer(found.device_id)],
            "session": None if not self._session else {
                "state": self._session.state, "code": self._session.code,
                "peer": self._session.peer_name, "failure": self._session.failure},
        })

    # ---- listening and dialling ----------------------------------------------------------------------------

    async def _reconcile(self) -> None:
        wants_sync = bool(self.settings.peers)
        if wants_sync and not self._sync_server:
            context = network.psk_server_context(self._key_for_identity)
            self._sync_server = await asyncio.start_server(
                lambda r, w: self._adopt(r, w, None), host="0.0.0.0", port=0, ssl=context,
                ssl_handshake_timeout=HANDSHAKE_SECONDS)
            await self.bonjour.advertise("sync", self._sync_server.sockets[0].getsockname()[1])
        elif not wants_sync and self._sync_server:
            self._sync_server.close()
            self._sync_server = None
            await self.bonjour.withdraw("sync")
        self._connect_to_peers()

    def _key_for_identity(self, identity: str) -> bytes | None:
        return self.store.load_key(identity) if self.settings.peer(identity) else None

    def _discovered(self, found: list[network.Discovered]) -> None:
        self.discovered = sorted(found, key=lambda item: item.name.lower())
        self._connect_to_peers()
        self._publish()

    def _connect_to_peers(self) -> None:
        """Of two paired computers only the one with the smaller id dials, so there is one connection per pair."""
        own = self.settings.device_id
        for peer in self.settings.peers:
            if not own < peer.id or peer.id in self.connections or peer.id in self._dialing:
                continue
            target = next((f for f in self.discovered if f.device_id == peer.id and not f.is_pairing), None)
            key = self.store.load_key(peer.id)
            if target and key:
                self._dialing.add(peer.id)
                asyncio.ensure_future(self._dial(target, peer.id, key))

    async def _dial(self, target: network.Discovered, peer_id: str, key: bytes) -> None:
        try:
            context = network.psk_client_context(self.settings.device_id, key)
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(target.host, target.port, ssl=context, server_hostname=None),
                HANDSHAKE_SECONDS)
            self._adopt(reader, writer, peer_id)
        except (OSError, asyncio.TimeoutError) as error:
            log.info("Could not reach %s: %s", target.name, error)
        finally:
            self._dialing.discard(peer_id)

    def _adopt(self, reader, writer, expected_peer: str | None) -> None:
        connection = network.Connection(reader, writer, self._receive, self._closed)
        connection.peer_id = expected_peer
        connection.expected_peer = expected_peer
        self._send_hello(connection)
        asyncio.ensure_future(connection.run())

    def _send_hello(self, connection: network.Connection) -> None:
        connection.send("hello", {"deviceID": self.settings.device_id, "name": self.settings.name,
                                  "wantsWallpaper": False, "wantsRoaming": self.settings.roaming,
                                  "appVersion": APP_VERSION, "platform": "windows"})

    def _closed(self, connection: network.Connection) -> None:
        peer_id = connection.peer_id
        if peer_id and self.connections.get(peer_id) is connection:
            del self.connections[peer_id]
            self.wants_roaming.pop(peer_id, None)
            self.versions.pop(peer_id, None)
            self.emit("peer_left", peer_id)
            self._publish()

    # ---- messages ------------------------------------------------------------------------------------------

    def _receive(self, connection: network.Connection, name: str, fields: dict) -> None:
        if name == "hello":
            return self._greeted(connection, fields)
        peer_id = connection.peer_id
        if not peer_id or self.connections.get(peer_id) is not connection:
            return
        if name in ("roamingHandoff", "roamingReturn"):
            try:
                visitor = protocol.Visitor.from_wire(fields.get("_0") or {})
            except (ValueError, TypeError):
                return
            if name == "roamingReturn":
                peer = self.settings.peer(peer_id)
                self.emit("returned", (visitor, peer.side if peer and peer.side else "right"))
            elif self.settings.roaming:
                self.emit("visitor", (visitor, peer_id))
            else:
                connection.send("roamingReturn", {"_0": visitor.to_wire()})
        # Wallpaper messages are not supported on Windows yet; the hello says so.

    def _greeted(self, connection: network.Connection, fields: dict) -> None:
        peer_id = fields.get("deviceID")
        expected = getattr(connection, "expected_peer", None)
        if not self.settings.peer(peer_id) or (expected and expected != peer_id):
            connection.close()
            return
        connection.peer_id = peer_id
        old = self.connections.get(peer_id)
        if old is not connection:
            if old:
                old.close()
            self.connections[peer_id] = connection
        self.wants_roaming[peer_id] = fields.get("wantsRoaming") is True
        self.versions[peer_id] = (fields.get("appVersion"), fields.get("platform"))
        self._publish()

    # ---- mascots -------------------------------------------------------------------------------------------

    def can_hand_off(self, side: str) -> bool:
        peer = self.settings.peer_on(side)
        return bool(peer and peer.id in self.connections and self.wants_roaming.get(peer.id))

    def hand_off(self, visitor: protocol.Visitor, side: str) -> None:
        peer = self.settings.peer_on(side)
        connection = self.connections.get(peer.id) if peer else None
        if connection:
            connection.send("roamingHandoff", {"_0": visitor.to_wire()})
        else:
            self.emit("returned", (visitor, side))

    def send_back(self, visitor: protocol.Visitor, peer_id: str) -> None:
        connection = self.connections.get(peer_id)
        if connection:
            connection.send("roamingReturn", {"_0": visitor.to_wire()})

    # ---- pairing -------------------------------------------------------------------------------------------

    def open_pairing(self) -> None:
        if self._pair_server is None:
            asyncio.ensure_future(self._open_pairing())

    async def _open_pairing(self) -> None:
        self._pair_server = await asyncio.start_server(self._pair_incoming, host="0.0.0.0", port=0)
        await self.bonjour.advertise("pair", self._pair_server.sockets[0].getsockname()[1])
        self._pair_closer = self.loop.call_later(PAIRING_WINDOW_SECONDS, self.close_pairing)
        self._publish()

    def close_pairing(self) -> None:
        if self._pair_closer:
            self._pair_closer.cancel()
            self._pair_closer = None
        if self._pair_server:
            self._pair_server.close()
            self._pair_server = None
        asyncio.ensure_future(self.bonjour.withdraw("pair"))
        if self._session and not self._session.is_final:
            self._session_send(self._session.cancel())
        self._end_session()
        self._publish()

    def pair_with(self, device_id: str) -> None:
        target = next((f for f in self.discovered if f.device_id == device_id and f.is_pairing), None)
        if target and self._pair_server and self._session is None:
            asyncio.ensure_future(self._pair_dial(target))

    async def _pair_dial(self, target: network.Discovered) -> None:
        try:
            reader, writer = await asyncio.wait_for(asyncio.open_connection(target.host, target.port), 10)
        except (OSError, asyncio.TimeoutError) as error:
            self.emit("problem", f"Could not reach {target.name}: {error}")
            return
        self._begin_session(reader, writer, is_initiator=True, peer_name=target.name)

    def _pair_incoming(self, reader, writer) -> None:
        if self._session is not None:
            writer.close()
            return
        self._begin_session(reader, writer, is_initiator=False, peer_name=None)

    def _begin_session(self, reader, writer, is_initiator: bool, peer_name: str | None) -> None:
        session = pairing.PairingSession(self.settings.device_id, self.settings.name, is_initiator)
        session.peer_name = peer_name
        connection = network.Connection(reader, writer, self._pair_message, self._pair_closed)
        self._session, self._session_connection = session, connection
        asyncio.ensure_future(connection.run())
        self._session_send(session.start())
        self._publish()

    def _session_send(self, messages: list) -> None:
        if self._session_connection:
            for name, fields in messages:
                self._session_connection.send(name, fields)

    def _pair_message(self, connection: network.Connection, name: str, fields: dict) -> None:
        if connection is not self._session_connection or not self._session:
            return
        self._session_send(self._session.receive(name, fields))
        self._after_step()

    def confirm_pairing(self) -> None:
        if self._session:
            messages = self._session.confirm()
            if messages:
                self._session_send(messages)
                self._after_step()

    def cancel_pairing(self) -> None:
        if self._session:
            self._session_send(self._session.cancel())
            self._end_session()
            self._publish()

    def _after_step(self) -> None:
        session = self._session
        if session and session.state == "finished" and session.result:
            result = session.result
            self.store.save_key(result.peer_id, result.key)
            self.settings = self.settings.adding(Peer(result.peer_id, result.peer_name, self.settings.free_side))
            self.store.save(self.settings)
            self.emit("paired", result.peer_name)
            self.loop.call_later(1, self.close_pairing)  # Let the last confirmation reach the other side.
            asyncio.ensure_future(self._reconcile())
        self._publish()

    def _pair_closed(self, connection: network.Connection) -> None:
        if connection is self._session_connection and self._session and not self._session.is_final:
            self._session.fail("The connection to the other computer was lost.")
            self._publish()

    def _end_session(self) -> None:
        connection = self._session_connection
        self._session, self._session_connection = None, None
        if connection:
            self.loop.call_later(1, connection.close)
