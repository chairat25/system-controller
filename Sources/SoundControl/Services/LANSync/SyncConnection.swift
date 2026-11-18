import Foundation
import Network
import OSLog
import SoundControlCore

/// One TCP or TLS connection to another Mac. Reads length-prefixed frames, writes messages and raw file bytes.
/// Everything runs on the main queue, so callbacks can touch main-actor state.
final class SyncConnection {
    private static let readChunk = 64 * 1024
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "LANSync")

    let connection: NWConnection
    /// Set once the Mac behind this connection is known (after a valid hello or pairing step).
    var peerID: String?

    var onReady: (() -> Void)?
    var onMessage: ((SyncMessage) -> Void)?
    var onRaw: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private var decoder = SyncFrameDecoder()
    private var isClosed = false

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.handle(state) }
        }
        connection.start(queue: .main)
    }

    func send(_ message: SyncMessage) {
        guard !isClosed, let payload = try? message.encoded() else { return }
        connection.send(content: SyncFraming.encode(kind: .message, payload: payload),
                        completion: .contentProcessed { [weak self] error in
            if let error { MainActor.assumeIsolated { self?.fail(error) } }
        })
    }

    /// Sends file bytes as one raw frame. `completion` runs when the data has been handed to the network.
    func sendRaw(_ data: Data, completion: @escaping (Bool) -> Void) {
        guard !isClosed else { return completion(false) }
        connection.send(content: SyncFraming.header(kind: .raw, length: data.count), isComplete: false,
                        completion: .contentProcessed { _ in })
        connection.send(content: data, isComplete: false, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                if let error { self?.fail(error) }
                completion(error == nil)
            }
        })
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            receive()
            onReady?()
        case let .failed(error):
            fail(error)
        case .cancelled:
            finish()
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.readChunk) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty { self.consume(data) }
                if let error { return self.fail(error) }
                if isComplete { return self.finish() }
                if !self.isClosed { self.receive() }
            }
        }
    }

    private func consume(_ data: Data) {
        do {
            let frames = try decoder.append(data)
            for frame in frames where !isClosed {
                switch frame.kind {
                case .message:
                    guard let message = try? SyncMessage.decode(frame.payload) else {
                        Self.logger.error("Dropped a message that could not be decoded")
                        continue
                    }
                    onMessage?(message)
                case .raw:
                    onRaw?(frame.payload)
                }
            }
        } catch {
            Self.logger.error("Closing a connection after a bad frame: \(String(describing: error), privacy: .public)")
            finish()
        }
    }

    private func fail(_ error: Error) {
        Self.logger.error("Connection failed: \(error.localizedDescription, privacy: .public)")
        finish()
    }

    private func finish() {
        guard !isClosed else { return }
        close()
        onClose?()
    }
}
