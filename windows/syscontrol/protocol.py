"""Wire format shared with the Mac app (see docs/LAN-PROTOCOL.md): framing, messages and roaming visitors."""
from __future__ import annotations

import base64
import json
import struct
from dataclasses import dataclass, field

SERVICE_TYPE = "_syscontrol._tcp.local."
FRAME_MESSAGE = 0
FRAME_RAW = 1
HEADER_SIZE = 5
MAXIMUM_MESSAGE_BYTES = 64 * 1024
MAXIMUM_RAW_BYTES = 20 * 1024 * 1024
MAXIMUM_ID_LENGTH = 64
MAXIMUM_NAME_LENGTH = 60

ANIMALS = ("cat", "pig", "puppy", "bunny", "panda", "penguin", "hippo", "tabby")
#: The closest animal Mac app 1.6.0 can draw, sent as `look`; `species` carries the exact one.
LEGACY = {"tabby": "cat"}
SCALE_RANGE = (0.75, 2.0)
#: Message fields that hold bytes (base64 in JSON, like Swift's `Data`).
BINARY_FIELDS = {"commitment", "publicKey"}


class FrameError(Exception):
    """A bad or oversized frame: the connection must be closed."""


def is_valid_id(value: object) -> bool:
    return (isinstance(value, str) and 0 < len(value) <= MAXIMUM_ID_LENGTH
            and all(33 <= ord(ch) < 127 for ch in value))


def clean_name(value: object, fallback: str = "Mac") -> str:
    text = "".join(ch for ch in str(value or "") if ch.isprintable()).strip()
    return text[:MAXIMUM_NAME_LENGTH] or fallback


def encode_frame(kind: int, payload: bytes) -> bytes:
    return struct.pack(">IB", len(payload), kind) + payload


class FrameDecoder:
    """Collects bytes and returns each complete (kind, payload) frame."""

    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, data: bytes) -> list[tuple[int, bytes]]:
        self._buffer += data
        frames = []
        while len(self._buffer) >= HEADER_SIZE:
            length, kind = struct.unpack(">IB", self._buffer[:HEADER_SIZE])
            if kind not in (FRAME_MESSAGE, FRAME_RAW):
                raise FrameError(f"unknown frame kind {kind}")
            limit = MAXIMUM_MESSAGE_BYTES if kind == FRAME_MESSAGE else MAXIMUM_RAW_BYTES
            if length > limit:
                raise FrameError(f"frame of {length} bytes is too large")
            if len(self._buffer) < HEADER_SIZE + length:
                break
            frames.append((kind, bytes(self._buffer[HEADER_SIZE:HEADER_SIZE + length])))
            del self._buffer[:HEADER_SIZE + length]
        return frames


def encode_message(case: str, /, **fields: object) -> bytes:
    """Swift's synthesized enum JSON: {"case": {"label": value}}; an unlabelled value is "_0"."""
    body = {key: base64.b64encode(value).decode() if isinstance(value, bytes) else value
            for key, value in fields.items() if value is not None}
    return json.dumps({case: body}, separators=(",", ":")).encode()


def decode_message(data: bytes) -> tuple[str, dict]:
    message = json.loads(data)
    if not isinstance(message, dict) or len(message) != 1:
        raise ValueError("not a message")
    (name, body), = message.items()
    if not isinstance(body, dict):
        raise ValueError("message body is not an object")
    return name, body


def decode_bytes(value: object) -> bytes:
    """Base64 from the wire; bytes are taken as they are (messages passed between sessions in memory)."""
    if isinstance(value, bytes):
        return value
    if not isinstance(value, str):
        raise ValueError("expected base64 text")
    return base64.b64decode(value, validate=True)


def _number(value: object, fallback: float) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value != value or abs(value) == float("inf"):
        return fallback
    return float(value)


@dataclass(frozen=True)
class Visitor:
    """A mascot handed between screens (Swift `RoamingObject`)."""

    id: str
    direction: str = "right"
    y_fraction: float = 1.0
    state: str = "walking"
    home: str | None = None
    look: str = "cat"
    hue: float | None = None
    scale: float | None = None
    flight: dict | None = field(default=None)

    @property
    def entry_edge(self) -> str:
        """The edge it walks in from: opposite to the one it left through."""
        return "left" if self.direction == "right" else "right"

    @staticmethod
    def from_wire(fields: dict) -> "Visitor":
        if not is_valid_id(fields.get("id")) or fields.get("kind") != "mascot":
            raise ValueError("not a mascot")
        species = fields.get("species")
        look = species if species in ANIMALS else fields.get("look")
        hue = fields.get("hue")
        scale = fields.get("scale")
        flight = fields.get("flight")
        if isinstance(flight, dict):
            flight = {"liftFraction": min(max(_number(flight.get("liftFraction"), 0), 0), 1),
                      "vx": min(max(_number(flight.get("vx"), 0), -6000), 6000),
                      "vy": min(max(_number(flight.get("vy"), 0), -6000), 6000)}
        else:
            flight = None
        home = fields.get("home")
        return Visitor(
            id=fields["id"],
            direction="left" if fields.get("direction") == "left" else "right",
            y_fraction=min(max(_number(fields.get("yFraction"), 1), 0), 1),
            state="resting" if fields.get("state") == "resting" else "walking",
            home=home if is_valid_id(home) else None,
            look=look if look in ANIMALS else "cat",
            hue=None if hue is None else _number(hue, 0) % 360,
            scale=None if scale is None else min(max(_number(scale, 1), SCALE_RANGE[0]), SCALE_RANGE[1]),
            flight=flight,
        )

    def to_wire(self) -> dict:
        wire = {"id": self.id, "kind": "mascot", "yFraction": self.y_fraction, "direction": self.direction,
                "state": self.state, "look": LEGACY.get(self.look, self.look), "species": self.look}
        if self.home:
            wire["home"] = self.home
        if self.hue is not None:
            wire["hue"] = self.hue
        if self.scale is not None:
            wire["scale"] = self.scale
        if self.flight:
            wire["flight"] = self.flight
        return wire
