import CryptoKit
import Foundation
import SoundControlCore

/// One pairing attempt over plain TCP. The initiator commits to its public key, the responder answers with
/// its own, the initiator reveals. Both then show the same six digits; the user compares them on both Macs and
/// taps Confirm on each. Only then is the shared key derived and handed out.
final class LANPairingSession {
    enum Phase: Equatable {
        case connecting
        case exchanging
        case confirming(code: String)
        case finished
        case failed(String)
    }

    struct Result {
        let peerID: String
        let peerName: String
        let key: Data
    }

    let connection: SyncConnection
    let isInitiator: Bool
    private(set) var phase = Phase.connecting
    private(set) var peerName: String?

    var onPhaseChange: ((Phase) -> Void)?
    var onPaired: ((Result) -> Void)?

    private let ownID: String
    private let ownName: String
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private var peerID: String?
    private var peerPublicKey: Data?
    private var peerCommitment: Data?
    private var hasConfirmed = false
    private var peerHasConfirmed = false

    init(connection: SyncConnection, isInitiator: Bool, ownID: String, ownName: String, expectedPeerName: String? = nil) {
        self.connection = connection
        self.isInitiator = isInitiator
        self.ownID = ownID
        self.ownName = ownName
        self.peerName = expectedPeerName
        connection.onReady = { [weak self] in self?.connected() }
        connection.onMessage = { [weak self] message in self?.receive(message) }
        connection.onClose = { [weak self] in self?.fail("The connection to the other Mac was lost.") }
    }

    func start() {
        connection.start()
    }

    /// The user compared the digits and they match.
    func confirm() {
        guard case .confirming = phase, !hasConfirmed else { return }
        hasConfirmed = true
        connection.send(.pairConfirm)
        completeIfBothConfirmed()
    }

    func cancel() {
        guard !isFinal else { return }
        connection.send(.pairCancel)
        fail("Pairing was cancelled.")
    }

    private var isFinal: Bool {
        switch phase {
        case .finished, .failed: true
        default: false
        }
    }

    private func connected() {
        guard isInitiator else { return }
        set(.exchanging)
        connection.send(.pairCommit(deviceID: ownID, name: ownName,
                                    commitment: PairingCode.commitment(of: privateKey.publicKey.rawRepresentation)))
    }

    private func receive(_ message: SyncMessage) {
        guard !isFinal else { return }
        switch message {
        case let .pairCommit(id, name, commitment) where !isInitiator && peerID == nil:
            guard accept(id, name) else { return }
            peerCommitment = commitment
            set(.exchanging)
            connection.send(.pairKey(deviceID: ownID, name: ownName, publicKey: privateKey.publicKey.rawRepresentation))
        case let .pairKey(id, name, publicKey) where isInitiator && peerID == nil:
            guard accept(id, name) else { return }
            peerPublicKey = publicKey
            connection.send(.pairReveal(publicKey: privateKey.publicKey.rawRepresentation))
            showCode()
        case let .pairReveal(publicKey) where !isInitiator && peerPublicKey == nil:
            guard let commitment = peerCommitment, PairingCode.isValid(commitment, for: publicKey) else {
                return fail("The other Mac did not follow the pairing steps. Nothing was paired.")
            }
            peerPublicKey = publicKey
            showCode()
        case .pairConfirm:
            guard case .confirming = phase else { return fail("The other Mac confirmed too early.") }
            peerHasConfirmed = true
            completeIfBothConfirmed()
        case .pairCancel:
            fail("The other Mac cancelled pairing.")
        default:
            fail("The other Mac sent something unexpected. Nothing was paired.")
        }
    }

    private func accept(_ id: String, _ name: String) -> Bool {
        guard PairedPeer.isValidID(id), id != ownID else {
            fail("The other Mac sent an invalid identity.")
            return false
        }
        peerID = id
        peerName = PairedPeer(id: id, name: name, side: .right).name
        return true
    }

    private func showCode() {
        guard let peerPublicKey else { return }
        let code = PairingCode.code(privateKey.publicKey.rawRepresentation, peerPublicKey)
        set(.confirming(code: code))
    }

    private func completeIfBothConfirmed() {
        guard hasConfirmed, peerHasConfirmed, let peerID, let peerPublicKey else { return }
        do {
            let key = try PairingCode.sharedKey(privateKey: privateKey, peerPublicKey: peerPublicKey)
            set(.finished)
            onPaired?(Result(peerID: peerID, peerName: peerName ?? "Mac", key: key))
        } catch {
            fail("The key exchange failed. Nothing was paired.")
        }
    }

    private func fail(_ reason: String) {
        guard !isFinal else { return }
        set(.failed(reason))
    }

    private func set(_ next: Phase) {
        guard next != phase else { return }
        phase = next
        onPhaseChange?(next)
    }
}
