import AppKit
import ImageIO
import OSLog
import SoundControlCore

/// Keeps the screen saver background and the desktop wallpaper the same on every paired Mac.
/// Each kind has one timestamp: when its current wallpaper was chosen, on any Mac. Peers swap timestamps when
/// they connect and whenever one changes; the Mac holding the older one pulls the file from the newer one.
final class WallpaperSyncer {
    /// What the syncer needs from the network layer and from the app.
    struct Link {
        /// Connected peers that want wallpapers.
        var peers: () -> [String]
        var send: (String, SyncMessage) -> Void
        var sendRaw: (String, Data, @escaping (Bool) -> Void) -> Void
        /// Name of the custom screen saver photo, if any.
        var screenSaverName: () -> String?
        /// The photo file is in place; show it on the screen saver.
        var screenSaverApplied: (String) -> Void
    }

    private static let logger = Logger(subsystem: "com.pond.soundcontrol", category: "WallpaperSync")
    private static let stampKeyPrefix = "lanSync.wallpaperStamp."
    private static let desktopPrefix = "desktop-"
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "tif", "tiff"]

    private let link: Link
    private let watcher = DesktopWallpaperWatcher()
    private let folder = ConfigStore.applicationSupport().appendingPathComponent("LANSync", isDirectory: true)
    private var state: WallpaperSyncState
    private var desktopFile: (url: URL, meta: WallpaperMeta)?
    /// Files other Macs asked for, per peer, waiting their turn: one is sent at a time.
    private var queued: [String: [(kind: WallpaperKind, timestamp: Double)]] = [:]
    private var sending: Set<String> = []
    /// What this Mac asked each peer for, so only an expected file is taken.
    private var requested: [String: [WallpaperKind: Double]] = [:]
    private var incoming: [String: WallpaperMeta] = [:]
    private var isRunning = false

    init(link: Link) {
        self.link = link
        let defaults = UserDefaults.standard
        let stamps = WallpaperKind.allCases.reduce(into: [WallpaperKind: Double]()) { result, kind in
            let value = defaults.double(forKey: Self.stampKeyPrefix + kind.rawValue)
            if value > 0 { result[kind] = value }
        }
        state = WallpaperSyncState(timestamps: stamps)
        watcher.onChange = { [weak self] url in self?.desktopChanged(url) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        desktopFile = existingDesktopFile()
        watcher.start()
    }

    func stop() {
        isRunning = false
        watcher.stop()
        queued = [:]
        sending = []
        requested = [:]
        incoming = [:]
    }

    func peerConnected(_ peerID: String) {
        guard isRunning else { return }
        WallpaperKind.allCases.forEach { offer($0, to: peerID) }
    }

    func peerDisconnected(_ peerID: String) {
        queued[peerID] = nil
        sending.remove(peerID)
        requested[peerID] = nil
        incoming[peerID] = nil
    }

    /// The user chose a new screen saver photo on this Mac.
    func screenSaverBackgroundChanged() {
        guard isRunning else { return }
        record(.screenSaver, at: Date().timeIntervalSince1970)
        announce(.screenSaver, except: nil)
    }

    // MARK: - Messages

    func handle(_ message: SyncMessage, from peerID: String) {
        guard isRunning else { return }
        switch message {
        case let .wallpaperOffer(meta): received(offer: meta, from: peerID)
        case let .wallpaperRequest(kind, timestamp): received(request: kind, timestamp: timestamp, from: peerID)
        case let .wallpaperData(meta): received(header: meta, from: peerID)
        default: break
        }
    }

    func handleRaw(_ data: Data, from peerID: String) {
        guard isRunning, let meta = incoming.removeValue(forKey: peerID), data.count == meta.size else { return }
        apply(meta, data, from: peerID)
    }

    private func received(offer meta: WallpaperMeta, from peerID: String) {
        switch state.decision(for: meta) {
        case .accept:
            guard requested[peerID]?[meta.kind] != meta.timestamp else { return }
            requested[peerID, default: [:]][meta.kind] = meta.timestamp
            link.send(peerID, .wallpaperRequest(kind: meta.kind, timestamp: meta.timestamp))
        case .tooLarge:
            Self.logger.notice("Ignored a wallpaper over the size limit")
        case .notNewer, .invalid:
            break
        }
    }

    private func received(request kind: WallpaperKind, timestamp: Double, from peerID: String) {
        // A request for a wallpaper that has been replaced is dropped: the peer got a newer offer already.
        guard currentMeta(kind)?.timestamp == timestamp else { return }
        queued[peerID, default: []].append((kind, timestamp))
        pump(peerID)
    }

    private func received(header meta: WallpaperMeta, from peerID: String) {
        incoming[peerID] = nil
        guard requested[peerID]?[meta.kind] == meta.timestamp, state.decision(for: meta) == .accept else { return }
        incoming[peerID] = meta
    }

    // MARK: - Sending

    private func offer(_ kind: WallpaperKind, to peerID: String) {
        guard let meta = currentMeta(kind) else { return }
        link.send(peerID, .wallpaperOffer(meta))
    }

    private func announce(_ kind: WallpaperKind, except skipped: String?) {
        for peerID in link.peers() where peerID != skipped { offer(kind, to: peerID) }
    }

    /// Sends the next queued file to a peer unless one is already on its way.
    private func pump(_ peerID: String) {
        guard !sending.contains(peerID), var waiting = queued[peerID], !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        queued[peerID] = waiting
        guard !WallpaperSyncPolicy.isSuperseded(queued: next.timestamp, latest: state.timestamp(of: next.kind)),
              let meta = currentMeta(next.kind), meta.timestamp == next.timestamp,
              let data = fileData(for: next.kind), data.count == meta.size else {
            return pump(peerID)
        }
        sending.insert(peerID)
        link.send(peerID, .wallpaperData(meta))
        link.sendRaw(peerID, data) { [weak self] _ in
            self?.sending.remove(peerID)
            self?.pump(peerID)
        }
    }

    private func currentMeta(_ kind: WallpaperKind) -> WallpaperMeta? {
        guard let timestamp = state.timestamp(of: kind) else { return nil }
        switch kind {
        case .screenSaver:
            guard let size = fileSize(ScreenSaverBackgroundStore.customImageURL) else { return nil }
            let name = link.screenSaverName() ?? "Background"
            return WallpaperMeta(kind: .screenSaver, timestamp: timestamp, fileName: name + ".jpg", size: size)
        case .desktop:
            guard let desktopFile, desktopFile.meta.timestamp == timestamp else { return nil }
            return desktopFile.meta
        }
    }

    private func fileData(for kind: WallpaperKind) -> Data? {
        let url = kind == .screenSaver ? ScreenSaverBackgroundStore.customImageURL : desktopFile?.url
        guard let url else { return nil }
        return autoreleasepool { try? Data(contentsOf: url) }
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    // MARK: - Local changes

    /// The user picked a new desktop wallpaper. A JPEG copy is made off the main thread; the new timestamp
    /// counts only once that copy exists, because there is nothing to offer before it.
    private func desktopChanged(_ source: URL) {
        // A wallpaper this app set from a peer's file is not a change by the user, whatever the poll saw.
        guard !source.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) else { return }
        guard !ScreenSaverBackgroundStore.isTCCProtectedPath(source) else {
            Self.logger.notice("Desktop wallpaper is in a protected folder; not shared")
            return
        }
        let stamp = Date().timeIntervalSince1970
        let target = desktopURL(timestamp: stamp, fileExtension: "jpg")
        let name = source.deletingPathExtension().lastPathComponent + ".jpg"
        let folder = folder
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let data = ScreenSaverBackgroundStore.downsampledJPEGData(from: source),
                  data.count <= WallpaperSyncPolicy.maximumBytes,
                  (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
                  (try? data.write(to: target, options: .atomic)) != nil else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.desktopCopyReady(target, name: name, stamp: stamp, size: data.count) }
            }
        }
    }

    private func desktopCopyReady(_ url: URL, name: String, stamp: Double, size: Int) {
        guard isRunning, record(.desktop, at: stamp) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        desktopFile = (url, WallpaperMeta(kind: .desktop, timestamp: stamp, fileName: name, size: size))
        removeOldDesktopFiles(keeping: url)
        announce(.desktop, except: nil)
    }

    // MARK: - Receiving a file

    private func apply(_ meta: WallpaperMeta, _ data: Data, from peerID: String) {
        // Checked again here: a newer wallpaper may have been chosen while the file was in flight.
        guard state.decision(for: meta) == .accept else { return }
        let isApplied = meta.kind == .screenSaver ? applyScreenSaver(meta, data) : applyDesktop(meta, data)
        guard isApplied else { return }
        record(meta.kind, at: meta.timestamp)
        // Other paired Macs may be older still: pass it on. The sender sees an equal timestamp and ignores it.
        announce(meta.kind, except: peerID)
    }

    private func applyScreenSaver(_ meta: WallpaperMeta, _ data: Data) -> Bool {
        let temp = folder.appendingPathComponent("incoming-" + meta.fileName)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: temp, options: .atomic)
            let name = try ScreenSaverBackgroundStore.importImage(from: temp)
            link.screenSaverApplied(name)
            return true
        } catch {
            Self.logger.error("Could not use the received screen saver photo: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func applyDesktop(_ meta: WallpaperMeta, _ data: Data) -> Bool {
        let fileExtension = Self.imageExtensions.contains(meta.fileExtension) ? meta.fileExtension : "jpg"
        let url = desktopURL(timestamp: meta.timestamp, fileExtension: fileExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            guard Self.isReadableImage(url) else {
                try? FileManager.default.removeItem(at: url)
                return false
            }
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        } catch {
            Self.logger.error("Could not set the received desktop wallpaper: \(error.localizedDescription, privacy: .public)")
            return false
        }
        desktopFile = (url, meta)
        removeOldDesktopFiles(keeping: url)
        watcher.markSeen()
        return true
    }

    private static func isReadableImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    // MARK: - State and files

    /// Remembers the moment a wallpaper was chosen. False when a newer one is already known.
    @discardableResult
    private func record(_ kind: WallpaperKind, at timestamp: Double) -> Bool {
        let next = state.recording(kind, at: timestamp)
        guard next != state else { return false }
        state = next
        UserDefaults.standard.set(timestamp, forKey: Self.stampKeyPrefix + kind.rawValue)
        return true
    }

    private func desktopURL(timestamp: Double, fileExtension: String) -> URL {
        folder.appendingPathComponent("\(Self.desktopPrefix)\(Int(timestamp * 1000)).\(fileExtension)")
    }

    private func removeOldDesktopFiles(keeping keep: URL) {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.lastPathComponent.hasPrefix(Self.desktopPrefix) && item != keep {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// After a restart: the desktop copy kept on disk, if it still matches the remembered timestamp.
    private func existingDesktopFile() -> (url: URL, meta: WallpaperMeta)? {
        guard let stamp = state.timestamp(of: .desktop) else { return nil }
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let prefix = "\(Self.desktopPrefix)\(Int(stamp * 1000))."
        guard let url = items.first(where: { $0.lastPathComponent.hasPrefix(prefix) }),
              let size = fileSize(url) else { return nil }
        return (url, WallpaperMeta(kind: .desktop, timestamp: stamp, fileName: url.lastPathComponent, size: size))
    }
}
