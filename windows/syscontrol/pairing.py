"""Pairing, the same steps as the Mac app: the initiator commits to its key, the responder answers with its own,
the initiator reveals. Both show six digits; after the user confirms on both, each derives the shared TLS key.
Sans-IO: `receive` and `confirm` return the messages to send as (name, fields) pairs."""
from __future__ import annotations

import hashlib
from dataclasses import dataclass

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from . import protocol

DIGITS = 6
HKDF_INFO = b"SystemController.LANSync.v1"


class PrivateKey:
    def __init__(self, key: X25519PrivateKey) -> None:
        self._key = key

    @staticmethod
    def generate() -> "PrivateKey":
        return PrivateKey(X25519PrivateKey.generate())

    @staticmethod
    def from_bytes(raw: bytes) -> "PrivateKey":
        return PrivateKey(X25519PrivateKey.from_private_bytes(raw))

    def public_bytes(self) -> bytes:
        return self._key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)

    def exchange(self, peer_public: bytes) -> bytes:
        return self._key.exchange(X25519PublicKey.from_public_bytes(peer_public))


def _sorted(first: bytes, second: bytes) -> tuple[bytes, bytes]:
    return (first, second) if first < second else (second, first)


def code(first: bytes, second: bytes) -> str:
    low, high = _sorted(first, second)
    value = int.from_bytes(hashlib.sha256(low + high).digest()[:4], "big")
    return f"{value % 10 ** DIGITS:0{DIGITS}d}"


def commitment(public_key: bytes) -> bytes:
    return hashlib.sha256(public_key).digest()


def shared_key(private_key: PrivateKey, peer_public: bytes) -> bytes:
    low, high = _sorted(private_key.public_bytes(), peer_public)
    secret = private_key.exchange(peer_public)
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=low + high, info=HKDF_INFO).derive(secret)


@dataclass(frozen=True)
class PairingResult:
    peer_id: str
    peer_name: str
    key: bytes


class PairingSession:
    """One attempt. `state` is connecting, exchanging, confirming, finished or failed."""

    def __init__(self, own_id: str, own_name: str, is_initiator: bool) -> None:
        self.own_id = own_id
        self.own_name = own_name
        self.is_initiator = is_initiator
        self.state = "connecting"
        self.code: str | None = None
        self.peer_name: str | None = None
        self.failure: str | None = None
        self.result: PairingResult | None = None
        self._key = PrivateKey.generate()
        self._peer_id: str | None = None
        self._peer_public: bytes | None = None
        self._peer_commitment: bytes | None = None
        self._confirmed = False
        self._peer_confirmed = False

    @property
    def is_final(self) -> bool:
        return self.state in ("finished", "failed")

    def start(self) -> list:
        """The connection is up. The initiator speaks first."""
        if not self.is_initiator:
            return []
        self.state = "exchanging"
        return [("pairCommit", {"deviceID": self.own_id, "name": self.own_name,
                                "commitment": commitment(self._key.public_bytes())})]

    def confirm(self) -> list:
        if self.state != "confirming" or self._confirmed:
            return []
        self._confirmed = True
        self._complete()
        return [("pairConfirm", {})]

    def cancel(self) -> list:
        if self.is_final:
            return []
        self.fail("Pairing was cancelled.")
        return [("pairCancel", {})]

    def fail(self, reason: str) -> None:
        if not self.is_final:
            self.state = "failed"
            self.failure = reason

    def receive(self, name: str, fields: dict) -> list:
        if self.is_final:
            return []
        try:
            return self._receive(name, fields)
        except (ValueError, KeyError, TypeError):
            self.fail("The other computer sent something unexpected. Nothing was paired.")
            return []

    def _receive(self, name: str, fields: dict) -> list:
        public = self._key.public_bytes()
        if name == "pairCommit" and not self.is_initiator and self._peer_id is None:
            self._accept(fields)
            self._peer_commitment = protocol.decode_bytes(fields["commitment"])
            self.state = "exchanging"
            return [("pairKey", {"deviceID": self.own_id, "name": self.own_name, "publicKey": public})]
        if name == "pairKey" and self.is_initiator and self._peer_id is None:
            self._accept(fields)
            self._peer_public = self._public(fields["publicKey"])
            self._show_code()
            return [("pairReveal", {"publicKey": public})]
        if name == "pairReveal" and not self.is_initiator and self._peer_public is None:
            revealed = self._public(fields["publicKey"])
            if self._peer_commitment is None or commitment(revealed) != self._peer_commitment:
                self.fail("The other computer did not follow the pairing steps. Nothing was paired.")
                return []
            self._peer_public = revealed
            self._show_code()
            return []
        if name == "pairConfirm":
            if self.state != "confirming":
                self.fail("The other computer confirmed too early.")
                return []
            self._peer_confirmed = True
            self._complete()
            return []
        if name == "pairCancel":
            self.fail("The other computer cancelled pairing.")
            return []
        self.fail("The other computer sent something unexpected. Nothing was paired.")
        return []

    @staticmethod
    def _public(value: object) -> bytes:
        raw = protocol.decode_bytes(value)
        if len(raw) != 32:
            raise ValueError("bad public key")
        return raw

    def _accept(self, fields: dict) -> None:
        peer_id = fields.get("deviceID")
        if not protocol.is_valid_id(peer_id) or peer_id == self.own_id:
            raise ValueError("invalid identity")
        self._peer_id = peer_id
        self.peer_name = protocol.clean_name(fields.get("name"))

    def _show_code(self) -> None:
        self.code = code(self._key.public_bytes(), self._peer_public)
        self.state = "confirming"

    def _complete(self) -> None:
        if not (self._confirmed and self._peer_confirmed and self._peer_id and self._peer_public):
            return
        key = shared_key(self._key, self._peer_public)
        self.state = "finished"
        self.result = PairingResult(self._peer_id, self.peer_name or "Mac", key)
