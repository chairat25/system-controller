import CryptoKit
import Foundation
import Network
import OSLog
import Security
import SoundControlCore

/// A Mac found on the network through Bonjour.
struct DiscoveredMac: Equatable, Identifiable {
    var id: String { serviceName }
    let serviceName: String
    let deviceID: String
    let name: String
    /// True when it is in its pairing window, false when it offers a synced (TLS) connection.
    let isPairing: Bool
    let endpoint: NWEndpoint
}

/// Bonjour listeners, the browser and outgoing connections. Pairing uses plain TCP; synced connections use
/// TLS 1.2 with a pre-shared key per paired Mac, so a Mac without the key cannot even finish the handshake.
final class LANSyncTransport {
    static let serviceType = "_syscontrol._tcp"
    private static let pairingSuffix = ".pair"
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "LANSync")

    /// Keys of the paired Macs, by device id.
    struct PeerKey {
        let peerID: String
        let key: Data
    }

    var onIncoming: ((SyncConnection, _ isPairing: Bool) -> Void)?
    var onDiscovered: (([DiscoveredMac]) -> Void)?

    private(set) var isBrowsing = false
    private var syncListener: NWListener?
    var hasSyncListener: Bool { syncListener != nil }
    private var pairingListener: NWListener?
    private var browser: NWBrowser?
    private let deviceID: String
    private let deviceName: String

    init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    // MARK: - Listening

    func startSyncListener(keys: [PeerKey]) {
        stopSyncListener()
        guard !keys.isEmpty else { return }
        let psks = keys.map { (identity: $0.peerID, key: $0.key) }
        startListener(parameters: Self.pskParameters(psks), serviceName: deviceID, mode: "sync", isPairing: false)
    }

    func stopSyncListener() {
        syncListener?.cancel()
        syncListener = nil
    }

    func startPairingListener() {
        stopPairingListener()
        startListener(parameters: .tcp, serviceName: deviceID + Self.pairingSuffix, mode: "pair", isPairing: true)
    }

    func stopPairingListener() {
        pairingListener?.cancel()
        pairingListener = nil
    }

    private func startListener(parameters: NWParameters, serviceName: String, mode: String, isPairing: Bool) {
        guard let listener = try? NWListener(using: parameters) else {
            Self.logger.error("Could not create a listener")
            return
        }
        let txt = NWTXTRecord(["id": deviceID, "name": deviceName, "mode": mode])
        listener.service = NWListener.Service(name: serviceName, type: Self.serviceType, txtRecord: txt)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.onIncoming?(SyncConnection(connection), isPairing) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener else { return }
                if case let .failed(error) = state {
                    Self.logger.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                    listener.cancel()
                    if isPairing, self.pairingListener === listener { self.stopPairingListener() }
                    if !isPairing, self.syncListener === listener { self.stopSyncListener() }
                }
            }
        }
        if isPairing { pairingListener = listener } else { syncListener = listener }
        listener.start(queue: .main)
    }

    // MARK: - Browsing

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.publish(results) }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            MainActor.assumeIsolated {
                guard let self, let browser else { return }
                switch state {
                case .ready:
                    self.isBrowsing = true
                case let .failed(error):
                    Self.logger.error("Browser failed: \(error.localizedDescription, privacy: .public)")
                    browser.cancel()
                    if self.browser === browser { self.stopBrowsing() }
                default:
                    break
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        onDiscovered?([])
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        let found: [DiscoveredMac] = results.compactMap { result in
            guard case let .service(serviceName, _, _, _) = result.endpoint,
                  case let .bonjour(record) = result.metadata,
                  case let .string(id)? = record.getEntry(for: "id"),
                  case let .string(mode)? = record.getEntry(for: "mode"),
                  id != deviceID, PairedPeer.isValidID(id) else { return nil }
            let name: String
            if case let .string(value)? = record.getEntry(for: "name") { name = value } else { name = "Mac" }
            return DiscoveredMac(serviceName: serviceName, deviceID: id, name: name,
                                 isPairing: mode == "pair", endpoint: result.endpoint)
        }
        onDiscovered?(found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    // MARK: - Connecting

    func connectForPairing(to mac: DiscoveredMac) -> SyncConnection {
        SyncConnection(NWConnection(to: mac.endpoint, using: .tcp))
    }

    func connectSynced(to mac: DiscoveredMac, key: Data) -> SyncConnection {
        SyncConnection(NWConnection(to: mac.endpoint, using: Self.pskParameters([(identity: deviceID, key: key)])))
    }

    func stopAll() {
        stopSyncListener()
        stopPairingListener()
        stopBrowsing()
    }

    // MARK: - TLS-PSK

    /// The server adds one PSK per paired Mac under that Mac's id; a client offers one PSK under its own id.
    static func pskParameters(_ psks: [(identity: String, key: Data)]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        for psk in psks {
            sec_protocol_options_add_pre_shared_key(options, dispatchData(psk.key) as __DispatchData,
                                                    dispatchData(Data(psk.identity.utf8)) as __DispatchData)
        }
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(options, suite)
        }
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }

    private static func dispatchData(_ data: Data) -> DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) }
    }
}
