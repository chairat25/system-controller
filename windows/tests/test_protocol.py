"""Wire compatibility with the Mac app. Fixtures were produced by the Swift encoder (docs/LAN-PROTOCOL.md)."""
import base64
import json

import pytest

from syscontrol import pairing, protocol

SWIFT_HELLO = '{"hello":{"deviceID":"A","appVersion":"1.7.0","platform":"macos","name":"Mac","wantsWallpaper":false,"wantsRoaming":true}}'
SWIFT_HANDOFF = ('{"roamingHandoff":{"_0":{"home":"HOME-ID","species":"tabby","flight":{"vy":-20,"liftFraction":0.5,'
                 '"vx":300},"direction":"right","yFraction":1,"hue":120,"id":"abcd1234-ef567890","kind":"mascot",'
                 '"state":"walking","scale":1.5,"look":"cat"}}}')


def test_decodes_swift_hello():
    name, fields = protocol.decode_message(SWIFT_HELLO.encode())
    assert name == "hello"
    assert fields["deviceID"] == "A" and fields["wantsRoaming"] is True and fields["platform"] == "macos"


def test_old_hello_without_version_decodes():
    name, fields = protocol.decode_message(b'{"hello":{"deviceID":"A","name":"Mac","wantsWallpaper":true,"wantsRoaming":true}}')
    assert name == "hello" and fields.get("appVersion") is None


def test_messages_match_swift_shape():
    assert json.loads(protocol.encode_message("pairConfirm")) == {"pairConfirm": {}}
    commit = protocol.encode_message("pairCommit", deviceID="A", name="Mac", commitment=b"\x01\x02\x03")
    assert json.loads(commit) == {"pairCommit": {"deviceID": "A", "name": "Mac", "commitment": "AQID"}}


def test_handoff_round_trip_keeps_species_hue_and_scale():
    name, fields = protocol.decode_message(SWIFT_HANDOFF.encode())
    visitor = protocol.Visitor.from_wire(fields["_0"])
    assert name == "roamingHandoff"
    assert visitor.look == "tabby" and visitor.hue == 120 and visitor.scale == 1.5
    assert visitor.flight == {"liftFraction": 0.5, "vx": 300, "vy": -20}
    wire = json.loads(protocol.encode_message("roamingHandoff", _0=visitor.to_wire()))["roamingHandoff"]["_0"]
    assert wire["look"] == "cat" and wire["species"] == "tabby"


def test_unknown_species_falls_back_to_legacy_look_and_unknown_look_to_cat():
    fields = {"id": "m", "kind": "mascot", "yFraction": 1, "direction": "left", "state": "walking",
              "look": "pig", "species": "dragon"}
    assert protocol.Visitor.from_wire(fields).look == "pig"
    assert protocol.Visitor.from_wire({**fields, "look": "unicorn", "species": None}).look == "cat"


def test_visitor_values_are_clamped():
    visitor = protocol.Visitor.from_wire({"id": "m", "kind": "mascot", "yFraction": 9, "direction": "left",
                                          "state": "walking", "hue": -30, "scale": 50})
    assert visitor.y_fraction == 1 and visitor.hue == 330 and visitor.scale == 2.0


def test_bad_ids_are_rejected():
    assert protocol.is_valid_id("ABC-123")
    assert not protocol.is_valid_id("")
    assert not protocol.is_valid_id("has space")
    assert not protocol.is_valid_id("x" * 65)


def test_framing_round_trip_and_limits():
    decoder = protocol.FrameDecoder()
    data = protocol.encode_frame(protocol.FRAME_MESSAGE, b"hello") + protocol.encode_frame(protocol.FRAME_RAW, b"xy")
    assert decoder.feed(data[:3]) == []
    assert decoder.feed(data[3:]) == [(protocol.FRAME_MESSAGE, b"hello"), (protocol.FRAME_RAW, b"xy")]
    with pytest.raises(protocol.FrameError):
        protocol.FrameDecoder().feed(b"\x00\x10\x00\x01\x00")  # message larger than 64 KB
    with pytest.raises(protocol.FrameError):
        protocol.FrameDecoder().feed(b"\x00\x00\x00\x01\x07x")  # unknown kind


def test_pairing_code_commitment_and_key_match_swift():
    a = bytes(range(32))
    b = bytes(255 - i for i in range(32))
    assert pairing.code(a, b) == pairing.code(b, a) == "646654"
    assert base64.b64encode(pairing.commitment(a)).decode() == "Yw3NKWbEM2aRElRIu7JbT/QSpJxzLbLIq8G4WBvXEN0="
    own = pairing.PrivateKey.from_bytes(bytes([7]) * 32)
    peer = pairing.PrivateKey.from_bytes(bytes([9]) * 32)
    assert base64.b64encode(own.public_bytes()).decode() == "E75P6uryBMf9M1j8nAByGIHRdCeBKCJ+xnTzf3/pe20="
    key = pairing.shared_key(own, peer.public_bytes())
    assert base64.b64encode(key).decode() == "okFHF4Kmz2V9jxTU5aIl4K6Z8mCLrau9saD2SWBkDRE="


def test_two_sessions_pair_with_each_other():
    initiator = pairing.PairingSession(own_id="PC-1", own_name="PC", is_initiator=True)
    responder = pairing.PairingSession(own_id="MAC-1", own_name="Mac", is_initiator=False)
    to_responder = initiator.start()
    to_initiator = []
    for _ in range(4):
        for message in to_responder:
            to_initiator += responder.receive(*message)
        to_responder = []
        for message in to_initiator:
            to_responder += initiator.receive(*message)
        to_initiator = []
    assert initiator.state == responder.state == "confirming"
    assert initiator.code == responder.code
    for message in initiator.confirm():
        responder.receive(*message)
    for message in responder.confirm():
        initiator.receive(*message)
    assert initiator.state == responder.state == "finished"
    assert initiator.result.key == responder.result.key and initiator.result.peer_id == "MAC-1"


def test_reveal_that_does_not_match_the_commitment_fails():
    responder = pairing.PairingSession(own_id="MAC-1", own_name="Mac", is_initiator=False)
    responder.receive("pairCommit", {"deviceID": "PC-1", "name": "PC", "commitment": base64.b64encode(b"x" * 32).decode()})
    responder.receive("pairReveal", {"publicKey": base64.b64encode(bytes(32)).decode()})
    assert responder.state == "failed"
