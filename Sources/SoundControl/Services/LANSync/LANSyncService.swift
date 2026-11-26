import Foundation
import Observation
import OSLog
import SoundControlCore
import SystemConfiguration

/// Lets Macs on the same network that the user has paired share wallpapers and a roaming desktop mascot.
/// It listens, browses and polls only while a sync toggle is on (plus a short, user-started pairing window).
@MainActor
@Observable
final class LANSyncService {
    /// What the service needs to know about, and to change in, the rest of the app.
    struct Hooks {
        var screenSaverName: () -> String?
        var screenSaverApplied: (String) -> Void
        var mascot: () -> Mascot
        var throwFrameRate: () -> ThrowFrameRate
        var mascotStyle: () -> MascotStyle
        var budget: () -> ResourceBudget
    }

    private static let maintenanceInterval: TimeInterval = 10
    private static let handshakeTimeout: TimeInterval = 15
    private static let deviceIDKey = "lanSync.deviceID"
    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "LANSync")

    private(set) var settings: LANSyncSettings
    /// Paired Macs with a live connection.
    private(set) var connectedPeerIDs: Set<String> = []
    /// What each connected computer said about itself in its hello: version and platform, nil when it is too old
    /// to say. The UI warns when they differ from this Mac's, since a visitor may then not look right.
    private(set) var peerVersions: [String: PeerVersion] = [:]

    struct PeerVersion: Equatable {
        let appVersion: String?
        let platform: String?
    }

    /// This build's version, sent in every hello.
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    /// Last problem worth showing: a settings or Keychain failure.
    private(set) var problem: String?
    @ObservationIgnored let pairing: LANSyncPairing

    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let transport: LANSyncTransport
    @ObservationIgnored private let mascots = DesktopMascotController()
    @ObservationIgnored private var wallpaper: WallpaperSyncer?
    @ObservationIgnored private var hooks: Hooks?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var discovered: [DiscoveredMac] = []
    /// Synced connections by peer id, after a valid hello.
    @ObservationIgnored private var connections: [String: SyncConnection] = [:]
    @ObservationIgnored private var peerWants: [String: (wallpaper: Bool, roaming: Bool)] = [:]
    /// Connections still waiting for the hello, with the time they started.
    @ObservationIgnored private var pending: [ObjectIdentifier: (connection: SyncConnection, since: Date)] = [:]
    @ObservationIgnored private var listenerPeerIDs: Set<String> = []
    /// Pairing keys read from disk once and kept here; the listener check runs every few seconds.
    @ObservationIgnored private var peerKeys: [String: Data] = [:]
    @ObservationIgnored private var maintenance: Timer?

    init() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: Self.deviceIDKey) ?? UUID().uuidString
        defaults.set(id, forKey: Self.deviceIDKey)
        deviceID = id
        let name = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        let loaded = LANSyncStore.load()
        settings = loaded
        let transport = LANSyncTransport(deviceID: id, deviceName: name)
        self.transport = transport
        pairing = LANSyncPairing(transport: transport, deviceID: id, deviceName: name)
        self.deviceName = name
        pairing.isPaired = { [weak self] in self?.settings.isPaired($0) ?? false }
        pairing.onPaired = { [weak self] in self?.finishPairing($0) }
        pairing.onWindowChange = { [weak self] in self?.reconcile() }
        transport.onIncoming = { [weak self] connection, isPairing in self?.incoming(connection, isPairing: isPairing) }
        transport.onDiscovered = { [weak self] macs in self?.found(macs) }
        mascots.canHandOff = { [weak self] side in self?.canHandOff(to: side) ?? false }
        mascots.handOff = { [weak self] object, side in self?.handOff(object, to: side) }
    }

    /// State for a layout-check script (see `UISnapshot`).
    var debugSummary: [String] {
        ["device \(deviceID)", "connected \(connectedPeerIDs.sorted())",
         "paired \(settings.pairedPeers.map { "\($0.name)/\($0.id)/\($0.side?.rawValue ?? "none")" })",
         "versions \(peerVersions.map { "\($0.key)=\($0.value.appVersion ?? "?")/\($0.value.platform ?? "?")" })",
         "pairing \(pairing.state) window=\(pairing.isWindowOpen) nearby=\(pairing.nearby.map(\.name))"]
            + mascots.debugSummary
    }

    /// Layout-check scripts: sends one of this Mac's own mascots over the edge right away.
    func debugPushMascot(to side: PeerSide) { mascots.debugPush(to: side) }

    /// The screen saver covers the desktop: the mascots stop moving until it closes.
    func setDesktopPaused(_ paused: Bool) { mascots.setPaused(paused) }

    /// The owner changed the size, number or colour of this Mac's mascots.
    func mascotStyleChanged() { mascots.applyStyle() }

    func start(hooks: Hooks) {
        guard !isStarted else { return }
        isStarted = true
        self.hooks = hooks
        mascots.mascot = hooks.mascot
        mascots.throwFrameRate = hooks.throwFrameRate
        mascots.style = hooks.mascotStyle
        mascots.budget = hooks.budget
        mascots.homeID = deviceID
        wallpaper = WallpaperSyncer(link: WallpaperSyncer.Link(
            peers: { [weak self] in self?.connectedPeers(wanting: \.wallpaper) ?? [] },
            send: { [weak self] id, message in self?.connections[id]?.send(message) },
            sendRaw: { [weak self] id, data, done in
                guard let connection = self?.connections[id] else { return done(false) }
                connection.sendRaw(data, completion: done)
            },
            screenSaverName: hooks.screenSaverName,
            screenSaverApplied: hooks.screenSaverApplied))
        reconcile()
    }

    // MARK: - Settings

    func update(_ transform: (LANSyncSettings) -> LANSyncSettings) {
        let next = transform(settings)
        guard next != settings else { return }
        let didChangeWants = next.isWallpaperSyncOn != settings.isWallpaperSyncOn
            || next.isMascotRoamingOn != settings.isMascotRoamingOn
        let wasWallpaperSyncOn = settings.isWallpaperSyncOn
        settings = next
        do {
            try LANSyncStore.save(next)
            if problem != nil { problem = nil }
        } catch {
            Self.logger.error("Saving LAN sync settings failed: \(error.localizedDescription, privacy: .public)")
            problem = "Could not save the sync settings: \(error.localizedDescription)"
        }
        reconcile()
        guard didChangeWants else { return }
        connections.values.forEach(sendHello)
        // Switching wallpaper sync on: tell the Macs already connected what this Mac has.
        if next.isWallpaperSyncOn, !wasWallpaperSyncOn {
            connectedPeers(wanting: \.wallpaper).forEach { wallpaper?.peerConnected($0) }
        }
    }

    func unpair(_ peerID: String) {
        connections[peerID]?.close()
        dropConnection(peerID)
        PeerKeychain.delete(peerID)
        peerKeys[peerID] = nil
        update { $0.removing(peerID) }
    }

    /// The user chose a new screen saver photo on this Mac.
    func screenSaverBackgroundChanged() {
        wallpaper?.screenSaverBackgroundChanged()
    }

    private func finishPairing(_ result: LANPairingSession.Result) {
        do {
            try PeerKeychain.save(result.key, for: result.peerID)
            peerKeys[result.peerID] = result.key
            // A Mac paired again keeps its id but brings a new key: the listener must take it.
            listenerPeerIDs = []
        } catch {
            Self.logger.error("Keychain save failed: \(error.localizedDescription, privacy: .public)")
            problem = "Could not store the pairing key: \(error.localizedDescription)"
            return
        }
        update { $0.adding(PairedPeer(id: result.peerID, name: result.peerName, side: $0.freeSide)) }
    }

    // MARK: - Starting and stopping

    /// Brings listeners, the browser and the features in line with the settings.
    private func reconcile() {
        guard isStarted else { return }
        let isRunning = settings.isActive && !settings.pairedPeers.isEmpty
        if isRunning { ensureSyncListener() } else { stopSyncing() }
        if isRunning || pairing.isWindowOpen { transport.startBrowsing() } else { transport.stopBrowsing() }
        if settings.isActive, settings.isWallpaperSyncOn { wallpaper?.start() } else { wallpaper?.stop() }
        if settings.isActive, settings.isMascotRoamingOn { mascots.start() } else { mascots.stop() }
        setMaintenance(isOn: isRunning)
        connectToPairedMacs()
    }

    private func key(for peerID: String) -> Data? {
        if let cached = peerKeys[peerID] { return cached }
        let loaded = PeerKeychain.load(peerID)
        peerKeys[peerID] = loaded
        return loaded
    }

    private func ensureSyncListener() {
        let keys = settings.pairedPeers.compactMap { peer in
            key(for: peer.id).map { LANSyncTransport.PeerKey(peerID: peer.id, key: $0) }
        }
        let ids = Set(keys.map(\.peerID))
        guard !transport.hasSyncListener || ids != listenerPeerIDs else { return }
        listenerPeerIDs = ids
        transport.startSyncListener(keys: keys)
    }

    private func stopSyncing() {
        transport.stopSyncListener()
        listenerPeerIDs = []
        pending.values.forEach { $0.connection.close() }
        pending = [:]
        connections.values.forEach { $0.close() }
        connections = [:]
        peerWants = [:]
        if !connectedPeerIDs.isEmpty { connectedPeerIDs = [] }
    }

    private func setMaintenance(isOn: Bool) {
        guard isOn else {
            maintenance?.invalidate()
            maintenance = nil
            return
        }
        guard maintenance == nil else { return }
        let timer = Timer(timeInterval: Self.maintenanceInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintain() }
        }
        timer.tolerance = Self.maintenanceInterval / 5
        RunLoop.main.add(timer, forMode: .common)
        maintenance = timer
    }

    /// Drops handshakes that never finished, then retries Macs that are in range but not connected.
    private func maintain() {
        let cutoff = Date().addingTimeInterval(-Self.handshakeTimeout)
        for (key, entry) in pending where entry.since < cutoff {
            entry.connection.close()
            pending[key] = nil
        }
        reconcile()
    }

    // MARK: - Connections

    private func found(_ macs: [DiscoveredMac]) {
        discovered = macs
        pairing.discovered(macs)
        connectToPairedMacs()
    }

    private func incoming(_ connection: SyncConnection, isPairing: Bool) {
        if isPairing { return pairing.accept(connection) }
        guard settings.isActive else { return connection.close() }
        adopt(connection)
    }

    /// Of two paired Macs only the one with the smaller id dials, so there is one connection per pair.
    private func connectToPairedMacs() {
        guard settings.isActive else { return }
        let connecting = Set(pending.values.compactMap(\.connection.peerID))
        for peer in settings.pairedPeers where deviceID < peer.id
            && connections[peer.id] == nil && !connecting.contains(peer.id) {
            guard let mac = discovered.first(where: { !$0.isPairing && $0.deviceID == peer.id }),
                  let key = key(for: peer.id) else { continue }
            let connection = transport.connectSynced(to: mac, key: key)
            connection.peerID = peer.id
            adopt(connection)
        }
    }

    private func adopt(_ connection: SyncConnection) {
        let key = ObjectIdentifier(connection)
        pending[key] = (connection, Date())
        connection.onReady = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.sendHello(on: connection)
        }
        connection.onMessage = { [weak self, weak connection] message in
            guard let self, let connection else { return }
            self.receive(message, on: connection)
        }
        connection.onRaw = { [weak self, weak connection] data in
            guard let self, let connection, let id = connection.peerID, self.connections[id] === connection else { return }
            self.wallpaper?.handleRaw(data, from: id)
        }
        connection.onClose = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.pending[ObjectIdentifier(connection)] = nil
            if let id = connection.peerID, self.connections[id] === connection { self.dropConnection(id) }
        }
        connection.start()
    }

    private func sendHello(on connection: SyncConnection) {
        connection.send(.hello(deviceID: deviceID, name: deviceName, wantsWallpaper: settings.isWallpaperSyncOn,
                               wantsRoaming: settings.isMascotRoamingOn, appVersion: Self.appVersion,
                               platform: "macos"))
    }

    private func receive(_ message: SyncMessage, on connection: SyncConnection) {
        switch message {
        case let .hello(id, _, wantsWallpaper, wantsRoaming, appVersion, platform):
            greeted(id, wantsWallpaper: wantsWallpaper, wantsRoaming: wantsRoaming, on: connection)
            guard connection.peerID == id else { return }
            let version = PeerVersion(appVersion: appVersion, platform: platform)
            if peerVersions[id] != version { peerVersions[id] = version }
        case .roamingHandoff(let object):
            guard let id = connection.peerID, connections[id] === connection else { return }
            // Never let a mascot vanish on the way: if it cannot stay here, it goes back to where it came from.
            if !settings.isMascotRoamingOn || !mascots.receive(object) { connection.send(.roamingReturn(object)) }
        case .roamingReturn(let object):
            guard let id = connection.peerID, connections[id] === connection else { return }
            mascots.returned(object, from: settings.peer(id: id)?.side ?? .right)
        default:
            guard let id = connection.peerID, connections[id] === connection else { return }
            wallpaper?.handle(message, from: id)
        }
    }

    /// A paired Mac said hello. Anyone else, or a Mac other than the one we dialled, is dropped.
    private func greeted(_ id: String, wantsWallpaper: Bool, wantsRoaming: Bool, on connection: SyncConnection) {
        guard settings.isPaired(id), connection.peerID == nil || connection.peerID == id else {
            pending[ObjectIdentifier(connection)] = nil
            return connection.close()
        }
        connection.peerID = id
        pending[ObjectIdentifier(connection)] = nil
        let isNew = connections[id] !== connection
        if isNew {
            connections[id]?.close()
            connections[id] = connection
        }
        let hadWallpaper = peerWants[id]?.wallpaper ?? false
        peerWants[id] = (wantsWallpaper, wantsRoaming)
        refreshConnected()
        if wantsWallpaper, isNew || !hadWallpaper { wallpaper?.peerConnected(id) }
    }

    private func dropConnection(_ id: String) {
        connections[id] = nil
        peerWants[id] = nil
        peerVersions[id] = nil
        mascots.peerLeft(id)
        wallpaper?.peerDisconnected(id)
        refreshConnected()
    }

    private func refreshConnected() {
        let ids = Set(connections.keys)
        if ids != connectedPeerIDs { connectedPeerIDs = ids }
    }

    private func connectedPeers(wanting want: KeyPath<(wallpaper: Bool, roaming: Bool), Bool>) -> [String] {
        connections.keys.filter { peerWants[$0]?[keyPath: want] ?? false }
    }

    // MARK: - Mascot

    private func canHandOff(to side: PeerSide) -> Bool {
        guard let peer = settings.peer(on: side) else { return false }
        return connections[peer.id] != nil && (peerWants[peer.id]?.roaming ?? false)
    }

    private func handOff(_ object: RoamingObject, to side: PeerSide) {
        guard let peer = settings.peer(on: side) else { return }
        connections[peer.id]?.send(.roamingHandoff(object))
    }
}
