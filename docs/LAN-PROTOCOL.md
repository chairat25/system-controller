# LAN sync protocol (for the Windows companion)

Reference taken from the Swift encoder, so another implementation can match it byte for byte.

- Bonjour service `_syscontrol._tcp`, TXT `id`, `name`, `mode` (`sync` | `pair`). Pairing service name is `<deviceID>.pair` (plain TCP); sync service name is `<deviceID>` (TLS 1.2, `TLS_PSK_WITH_AES_128_GCM_SHA256`, PSK identity = the dialler's device id, key = 32-byte pairing key).
- Of two paired devices only the one with the smaller device id dials.
- Frame: 4-byte big-endian payload length, 1 byte kind (0 = JSON message, max 64 KB; 1 = raw file bytes), payload.
- Pairing: initiator `pairCommit` (SHA-256 of its Curve25519 public key) → responder `pairKey` → initiator `pairReveal` → both show the code → both send `pairConfirm`.
  - Code: SHA-256(lowKey ‖ highKey) (keys sorted lexicographically), first 4 bytes big-endian mod 10^6, zero-padded to 6 digits.
  - Key: HKDF-SHA256(X25519 secret, salt = lowKey ‖ highKey, info = `SystemController.LANSync.v1`, 32 bytes).

## Messages (Swift synthesized enum JSON; `Data` is base64)

```
{"hello":{"deviceID":"A","name":"Mac","wantsWallpaper":false,"wantsRoaming":true,"appVersion":"1.7.0","platform":"macos"}}
{"pairCommit":{"deviceID":"A","name":"Mac","commitment":"AQID"}}
{"pairKey":{"deviceID":"B","name":"PC","publicKey":"BA=="}}
{"pairReveal":{"publicKey":"BQ=="}}
{"pairConfirm":{}}
{"pairCancel":{}}
{"roamingHandoff":{"_0":{"id":"abcd1234-ef567890","kind":"mascot","yFraction":1,"direction":"right","state":"walking","home":"HOME-ID","look":"cat","species":"tabby","flight":{"liftFraction":0.5,"vx":300,"vy":-20},"hue":120,"scale":1.5}}}
{"roamingReturn":{"_0":{ ...same object... }}}
```

`look` only ever names an animal 1.6.0 knows (`Mascot.legacy`); `species` is the exact animal.

## Test vectors

- keys a = bytes 0..31, b = bytes 255..224 → code `646654` (either order)
- commitment(a) = `Yw3NKWbEM2aRElRIu7JbT/QSpJxzLbLIq8G4WBvXEN0=`
- private keys 32×`0x07` and 32×`0x09`: public `E75P6uryBMf9M1j8nAByGIHRdCeBKCJ+xnTzf3/pe20=` / `V9tLNZ8jrl4Ubk4lEgVnBHIlBjSMFQwUdT0Mkz0E1CE=`, shared key `okFHF4Kmz2V9jxTU5aIl4K6Z8mCLrau9saD2SWBkDRE=`
