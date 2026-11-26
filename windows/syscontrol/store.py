"""Settings and pairing keys on disk: %APPDATA%\\SystemController on Windows, ~/.syscontrol elsewhere."""
from __future__ import annotations

import json
import logging
import os
import re
import socket
import uuid
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path

from . import protocol

log = logging.getLogger("syscontrol.store")
MAXIMUM_PEERS = 8


def default_folder() -> Path:
    override = os.environ.get("SYSCONTROL_DATA")
    if override:
        return Path(override)
    base = os.environ.get("APPDATA")
    return Path(base) / "SystemController" if base else Path.home() / ".syscontrol"


@dataclass(frozen=True)
class Peer:
    id: str
    name: str
    side: str | None  # "left", "right" or None (not beside this screen)


@dataclass(frozen=True)
class Settings:
    device_id: str
    name: str
    animal: str = "cat"
    hue: float = 0.0
    scale: float = 1.0
    count: int = 1
    roaming: bool = True
    peers: tuple[Peer, ...] = field(default_factory=tuple)

    def peer(self, peer_id: str) -> Peer | None:
        return next((peer for peer in self.peers if peer.id == peer_id), None)

    def peer_on(self, side: str) -> Peer | None:
        return next((peer for peer in self.peers if peer.side == side), None)

    @property
    def free_side(self) -> str | None:
        return next((side for side in ("right", "left") if self.peer_on(side) is None), None)

    def adding(self, peer: Peer) -> "Settings":
        existing = self.peer(peer.id)
        if existing:
            return replace(self, peers=tuple(Peer(p.id, peer.name, p.side) if p.id == peer.id else p
                                             for p in self.peers))
        return replace(self, peers=(self.peers + (peer,))[:MAXIMUM_PEERS])

    def removing(self, peer_id: str) -> "Settings":
        return replace(self, peers=tuple(p for p in self.peers if p.id != peer_id))

    def with_side(self, peer_id: str, side: str | None) -> "Settings":
        """Only one computer sits beyond each edge: the one that held it before is moved off it."""
        def placed(peer: Peer) -> Peer:
            if peer.id == peer_id:
                return Peer(peer.id, peer.name, side)
            return Peer(peer.id, peer.name, None) if side and peer.side == side else peer
        return replace(self, peers=tuple(placed(p) for p in self.peers))


def _clean(raw: dict) -> Settings:
    device_id = raw.get("device_id")
    if not protocol.is_valid_id(device_id):
        device_id = str(uuid.uuid4()).upper()
    peers = []
    for item in raw.get("peers") or []:
        if isinstance(item, dict) and protocol.is_valid_id(item.get("id")):
            side = item.get("side") if item.get("side") in ("left", "right") else None
            peers.append(Peer(item["id"], protocol.clean_name(item.get("name")), side))
    animal = raw.get("animal") if raw.get("animal") in protocol.ANIMALS else "cat"
    scale = raw.get("scale") if isinstance(raw.get("scale"), (int, float)) else 1.0
    hue = raw.get("hue") if isinstance(raw.get("hue"), (int, float)) else 0.0
    count = raw.get("count") if isinstance(raw.get("count"), int) else 1
    return Settings(device_id=device_id, name=protocol.clean_name(raw.get("name") or socket.gethostname(), "PC"),
                    animal=animal, hue=float(hue) % 360, scale=min(max(float(scale), 0.75), 2.0),
                    count=min(max(count, 1), 6), roaming=raw.get("roaming", True) is not False,
                    peers=tuple(peers[:MAXIMUM_PEERS]))


class Store:
    def __init__(self, folder: Path | None = None) -> None:
        self.folder = folder or default_folder()
        self._settings_file = self.folder / "settings.json"
        self._keys = self.folder / "PeerKeys"

    def load(self) -> Settings:
        try:
            raw = json.loads(self._settings_file.read_text(encoding="utf-8"))
        except FileNotFoundError:
            raw = {}
        except (OSError, ValueError) as error:
            log.error("Settings were unreadable and were reset: %s", error)
            raw = {}
        settings = _clean(raw if isinstance(raw, dict) else {})
        self.save(settings)
        return settings

    def save(self, settings: Settings) -> None:
        self.folder.mkdir(parents=True, exist_ok=True)
        data = asdict(settings)
        temporary = self._settings_file.with_suffix(".tmp")
        temporary.write_text(json.dumps(data, indent=2), encoding="utf-8")
        temporary.replace(self._settings_file)

    def _key_file(self, peer_id: str) -> Path:
        return self._keys / (re.sub(r"[^A-Za-z0-9-]", "_", peer_id) + ".key")

    def save_key(self, peer_id: str, key: bytes) -> None:
        self._keys.mkdir(parents=True, exist_ok=True)
        path = self._key_file(peer_id)
        path.write_bytes(key)
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass

    def load_key(self, peer_id: str) -> bytes | None:
        try:
            return self._key_file(peer_id).read_bytes()
        except OSError:
            return None

    def delete_key(self, peer_id: str) -> None:
        try:
            self._key_file(peer_id).unlink()
        except OSError:
            pass
