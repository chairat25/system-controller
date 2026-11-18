import Foundation
import Observation
import SoundControlCore

/// The pairing window and the one pairing attempt running inside it. Nothing listens for pairing until the user
/// opens the window, and the window shuts by itself after two minutes.
@MainActor
@Observable
final class LANSyncPairing {
    enum State: Equatable {
        case idle
        case connecting(peerName: String)
        case confirming(code: String, peerName: String)
        case failed(String)
    }

    static let windowDuration: TimeInterval = 120
    private static let finishDelay: TimeInterval = 1

    private(set) var state = State.idle
    private(set) var isWindowOpen = false
    /// Macs in their pairing window that this Mac is not paired with yet.
    private(set) var nearby: [DiscoveredMac] = []

    @ObservationIgnored private let transport: LANSyncTransport
    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let deviceName: String
    /// Wired by the service right after it is created.
    @ObservationIgnored var isPaired: (String) -> Bool = { _ in false }
    @ObservationIgnored var onPaired: (LANPairingSession.Result) -> Void = { _ in }
    @ObservationIgnored var onWindowChange: () -> Void = {}
    @ObservationIgnored private var session: LANPairingSession?
    @ObservationIgnored private var closeTimer: Timer?
    @ObservationIgnored private var discoveredPairing: [DiscoveredMac] = []

    init(transport: LANSyncTransport, deviceID: String, deviceName: String) {
        self.transport = transport
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    // MARK: - Window

    func openWindow() {
        guard !isWindowOpen else { return }
        isWindowOpen = true
        set(.idle)
        refreshNearby()
        transport.startPairingListener()
        closeTimer = Timer.scheduledTimer(withTimeInterval: Self.windowDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeWindow() }
        }
        onWindowChange()
    }

    func closeWindow() {
        guard isWindowOpen else { return }
        closeTimer?.invalidate()
        closeTimer = nil
        isWindowOpen = false
        session?.cancel()
        retireSession()
        transport.stopPairingListener()
        discoveredPairing = []
        if !nearby.isEmpty { nearby = [] }
        set(.idle)
        onWindowChange()
    }

    /// The browser found Macs; the ones in their pairing window are offered, minus those already paired.
    func discovered(_ macs: [DiscoveredMac]) {
        discoveredPairing = macs.filter(\.isPairing)
        refreshNearby()
    }

    private func refreshNearby() {
        let offered = isWindowOpen ? discoveredPairing.filter { !isPaired($0.deviceID) } : []
        if offered != nearby { nearby = offered }
    }

    // MARK: - Attempt

    func pair(with mac: DiscoveredMac) {
        guard isWindowOpen, session == nil else { return }
        attach(LANPairingSession(connection: transport.connectForPairing(to: mac), isInitiator: true,
                                 ownID: deviceID, ownName: deviceName, expectedPeerName: mac.name))
    }

    /// Another Mac connected to the pairing listener.
    func accept(_ connection: SyncConnection) {
        guard isWindowOpen, session == nil else { return connection.close() }
        attach(LANPairingSession(connection: connection, isInitiator: false, ownID: deviceID, ownName: deviceName))
    }

    func confirm() { session?.confirm() }

    func cancel() {
        session?.cancel()
        retireSession()
        set(.idle)
    }

    private func attach(_ next: LANPairingSession) {
        session = next
        next.onPhaseChange = { [weak self, weak next] phase in
            guard let self, let next, self.session === next else { return }
            self.phaseChanged(phase, in: next)
        }
        next.onPaired = { [weak self] result in
            guard let self else { return }
            self.onPaired(result)
            self.retireSession()
            self.closeWindow()
        }
        set(.connecting(peerName: next.peerName ?? "a Mac"))
        next.start()
    }

    private func phaseChanged(_ phase: LANPairingSession.Phase, in session: LANPairingSession) {
        let name = session.peerName ?? "a Mac"
        switch phase {
        case .connecting, .exchanging:
            set(.connecting(peerName: name))
        case let .confirming(code):
            set(.confirming(code: code, peerName: name))
        case .finished:
            break
        case let .failed(reason):
            retireSession()
            set(.failed(reason))
        }
    }

    /// Lets the last bytes (our confirmation) reach the other Mac before the connection closes.
    private func retireSession() {
        guard let finished = session else { return }
        session = nil
        finished.onPhaseChange = nil
        finished.onPaired = nil
        let connection = finished.connection
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishDelay) { connection.close() }
    }

    private func set(_ next: State) {
        if next != state { state = next }
    }
}
