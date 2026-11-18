import CryptoKit
import Foundation

/// The six digits both Macs show during pairing, and the key they agree on once the user confirms.
public enum PairingCode {
    public static let digitCount = 6
    private static let hkdfInfo = Data("SystemController.LANSync.v1".utf8)

    /// Same digits on both sides: SHA-256 of the two public keys in sorted order.
    public static func code(_ first: Data, _ second: Data) -> String {
        let (low, high) = sorted(first, second)
        let digest = SHA256.hash(data: low + high)
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let modulus = UInt32(pow(10, Double(digitCount)))
        return String(format: "%0\(digitCount)d", value % modulus)
    }

    /// Sent before the initiator sees the other key, so nobody in between can pick keys that show equal digits.
    public static func commitment(of publicKey: Data) -> Data {
        Data(SHA256.hash(data: publicKey))
    }

    public static func isValid(_ commitment: Data, for publicKey: Data) -> Bool {
        self.commitment(of: publicKey) == commitment
    }

    /// The 32-byte key for the TLS connection: HKDF-SHA256 over the ECDH secret, salted with both public keys.
    public static func sharedKey(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicKey: Data) throws -> Data {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let (low, high) = sorted(privateKey.publicKey.rawRepresentation, peerPublicKey)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: low + high, sharedInfo: hkdfInfo, outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    private static func sorted(_ first: Data, _ second: Data) -> (Data, Data) {
        first.lexicographicallyPrecedes(second) ? (first, second) : (second, first)
    }
}
