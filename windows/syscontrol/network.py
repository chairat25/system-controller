"""Bonjour discovery and advertising, TLS-PSK contexts and framed connections, all on one asyncio loop."""
from __future__ import annotations

import asyncio
import logging
import os
import socket
import ssl
from dataclasses import dataclass
from typing import Callable

import ifaddr
from zeroconf import IPVersion, ServiceStateChange
from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf

from . import protocol

log = logging.getLogger("syscontrol.network")
READ_CHUNK = 64 * 1024
CIPHER = "PSK-AES128-GCM-SHA256"
PAIR_SUFFIX = ".pair"


@dataclass(frozen=True)
class Discovered:
    """A computer found through Bonjour: in its pairing window, or offering a synced (TLS) connection."""

    service_name: str
    device_id: str
    name: str
    is_pairing: bool
    host: str
    port: int


def psk_server_context(lookup: Callable[[str], bytes | None]) -> ssl.SSLContext:
    """TLS 1.2 server with one pre-shared key per paired computer, chosen by the identity the client sends."""
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.set_ciphers(CIPHER)
    context.set_psk_server_callback(lambda identity: lookup(identity or "") or b"")
    return context


def psk_client_context(identity: str, key: bytes) -> ssl.SSLContext:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.set_ciphers(CIPHER)
    context.set_psk_client_callback(lambda hint: (identity, key))
    return context


class Connection:
    """One framed connection. `on_message(connection, name, fields)` runs for each JSON message."""

    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter,
                 on_message: Callable, on_close: Callable) -> None:
        self.reader = reader
        self.writer = writer
        self.peer_id: str | None = None
        self.on_message = on_message
        self.on_close = on_close
        self.is_closed = False
        self._decoder = protocol.FrameDecoder()

    def send(self, case: str, fields: dict | None = None) -> None:
        if self.is_closed:
            return
        payload = protocol.encode_message(case, **(fields or {}))
        self.writer.write(protocol.encode_frame(protocol.FRAME_MESSAGE, payload))

    async def run(self) -> None:
        try:
            while not self.is_closed:
                data = await self.reader.read(READ_CHUNK)
                if not data:
                    break
                for kind, payload in self._decoder.feed(data):
                    if kind != protocol.FRAME_MESSAGE:
                        continue  # Wallpaper bytes: not supported on Windows yet.
                    try:
                        name, fields = protocol.decode_message(payload)
                    except ValueError as error:
                        log.warning("Dropped a message that could not be decoded: %s", error)
                        continue
                    self.on_message(self, name, fields)
        except (ConnectionError, ssl.SSLError, protocol.FrameError, asyncio.IncompleteReadError, OSError) as error:
            log.info("Connection closed: %s", error)
        finally:
            self.close()

    def close(self) -> None:
        if self.is_closed:
            return
        self.is_closed = True
        try:
            self.writer.close()
        except (ConnectionError, OSError, RuntimeError):
            pass
        self.on_close(self)


#: Testing both apps on one Mac: macOS sees this companion's packets on the loopback interface, so it must answer
#: there too. Never needed between two real computers.
SAME_MACHINE_TEST = os.environ.get("SYSCONTROL_LOOPBACK") == "1"


def local_addresses() -> list[str]:
    addresses = []
    for adapter in ifaddr.get_adapters():
        for ip in adapter.ips:
            if isinstance(ip.ip, str) and not ip.ip.startswith(("127.", "169.254.")):
                addresses.append(ip.ip)
    if SAME_MACHINE_TEST:
        addresses.append("127.0.0.1")
    return addresses or ["127.0.0.1"]


class Bonjour:
    """Advertises this computer's listeners and keeps a list of the others."""

    def __init__(self, own_id: str, own_name: str, on_change: Callable[[list[Discovered]], None]) -> None:
        self.own_id = own_id
        self.own_name = own_name
        self.on_change = on_change
        self.found: dict[str, Discovered] = {}
        self._zeroconf: AsyncZeroconf | None = None
        self._browser: AsyncServiceBrowser | None = None
        self._registered: dict[str, AsyncServiceInfo] = {}

    async def start(self) -> None:
        interfaces = local_addresses() if SAME_MACHINE_TEST else None
        self._zeroconf = (AsyncZeroconf(interfaces=interfaces, ip_version=IPVersion.V4Only) if interfaces
                          else AsyncZeroconf(ip_version=IPVersion.V4Only))
        self._browser = AsyncServiceBrowser(self._zeroconf.zeroconf, protocol.SERVICE_TYPE,
                                            handlers=[self._changed])

    async def stop(self) -> None:
        for mode in list(self._registered):
            await self.withdraw(mode)
        if self._browser:
            await self._browser.async_cancel()
        if self._zeroconf:
            await self._zeroconf.async_close()

    async def advertise(self, mode: str, port: int) -> None:
        """mode is "sync" (instance name = device id) or "pair" (device id + ".pair")."""
        await self.withdraw(mode)
        instance = self.own_id + (PAIR_SUFFIX if mode == "pair" else "")
        info = AsyncServiceInfo(
            protocol.SERVICE_TYPE, f"{instance}.{protocol.SERVICE_TYPE}",
            addresses=[socket.inet_aton(ip) for ip in local_addresses()], port=port,
            properties={"id": self.own_id, "name": self.own_name, "mode": mode}, server=f"{self.own_id}.local.")
        await self._zeroconf.async_register_service(info, allow_name_change=True)
        self._registered[mode] = info

    async def withdraw(self, mode: str) -> None:
        info = self._registered.pop(mode, None)
        if info and self._zeroconf:
            await self._zeroconf.async_unregister_service(info)

    def _changed(self, zeroconf, service_type: str, name: str, state_change: ServiceStateChange) -> None:
        if state_change is ServiceStateChange.Removed:
            if self.found.pop(name, None):
                self.on_change(list(self.found.values()))
            return
        asyncio.ensure_future(self._resolve(service_type, name))

    async def _resolve(self, service_type: str, name: str) -> None:
        info = AsyncServiceInfo(service_type, name)
        if not await info.async_request(self._zeroconf.zeroconf, 3000):
            return
        text = {key.decode(errors="ignore"): (value or b"").decode(errors="ignore")
                for key, value in (info.properties or {}).items()}
        device_id = text.get("id", "")
        addresses = info.parsed_addresses(IPVersion.V4Only)
        if device_id == self.own_id or not protocol.is_valid_id(device_id) or not addresses or not info.port:
            return
        found = Discovered(service_name=name, device_id=device_id, name=protocol.clean_name(text.get("name")),
                           is_pairing=text.get("mode") == "pair", host=addresses[0], port=info.port)
        if self.found.get(name) != found:
            self.found[name] = found
            self.on_change(list(self.found.values()))
