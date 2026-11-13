import AppKit
import CryptoKit
import Foundation
import Observation
import OSLog
import SoundControlCore

/// Checks GitHub Releases (`chairat25/system-controller`) for newer versions, verifies the archive's
/// SHA-256 digest and code signature, and installs + relaunches when the screen saver is unlocked.
@MainActor
@Observable
final class AutoUpdater {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(version: String)
        case downloading(version: String)
        case installing(version: String)
        case failed(String)
    }

    private static let repo = "chairat25/system-controller"
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    private static let checkInterval: TimeInterval = 4 * 3600
    private static let initialDelay: TimeInterval = 6
    private static let fallbackVersion = "1.4.0"

    private(set) var status: Status = .idle
    private(set) var latestVersion: String?
    private(set) var lastCheckedAt: Date?

    @ObservationIgnored private var isAutoUpdateEnabled: () -> Bool = { true }
    @ObservationIgnored private var isLocked: () -> Bool = { false }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var pendingRelease: ReleaseAssetInfo?
    @ObservationIgnored private let logger = Logger(subsystem: "com.pond.soundcontrol", category: "AutoUpdater")

    var currentVersionString: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.fallbackVersion : trimmed
    }

    var isBusyUpdating: Bool { isBusy }

    var statusText: String {
        switch status {
        case .idle:
            "Up to date (\(currentVersionString))"
        case .checking:
            "Checking for updates…"
        case .upToDate(let version):
            "Up to date (\(version))"
        case .updateAvailable(let version):
            "Update v\(version) ready"
        case .downloading(let version):
            "Downloading v\(version)…"
        case .installing(let version):
            "Installing v\(version)…"
        case .failed(let message):
            message
        }
    }

    func start(isAutoUpdateEnabled: @escaping () -> Bool, isLocked: @escaping () -> Bool) {
        self.isAutoUpdateEnabled = isAutoUpdateEnabled
        self.isLocked = isLocked
        guard timer == nil else { return }

        let periodic = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isAutoUpdateEnabled() else { return }
                self.checkForUpdates(userInitiated: false)
            }
        }
        periodic.tolerance = 300
        timer = periodic

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isAutoUpdateEnabled() else { return }
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    /// Installs any update that was deferred while the screen saver or keyboard lock was active.
    func notifyUnlocked() {
        guard !isBusy, !isLocked(), let pending = pendingRelease else { return }
        pendingRelease = nil
        Task { await installRelease(pending) }
    }

    func checkForUpdates(userInitiated: Bool = true) {
        guard !isBusy else { return }
        isBusy = true
        setStatus(.checking)

        Task {
            defer { isBusy = false }
            do {
                let release = try await fetchLatestRelease()
                lastCheckedAt = Date()
                if latestVersion != release.version.description {
                    latestVersion = release.version.description
                }
                let current = AppVersion(parsing: currentVersionString) ?? AppVersion(major: 0, minor: 0, patch: 0)
                guard release.version > current else {
                    pendingRelease = nil
                    setStatus(.upToDate(version: current.description))
                    return
                }

                if isLocked() {
                    pendingRelease = release
                    setStatus(.updateAvailable(version: release.version.description))
                    return
                }

                if userInitiated || isAutoUpdateEnabled() {
                    await performInstall(release)
                } else {
                    pendingRelease = release
                    setStatus(.updateAvailable(version: release.version.description))
                }
            } catch {
                logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                if userInitiated {
                    setStatus(.failed("Could not check for updates: \(error.localizedDescription)"))
                } else if case .checking = status {
                    setStatus(.idle)
                }
            }
        }
    }

    private func installRelease(_ release: ReleaseAssetInfo) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await performInstall(release)
    }

    private func performInstall(_ release: ReleaseAssetInfo) async {
        guard !isLocked() else {
            pendingRelease = release
            setStatus(.updateAvailable(version: release.version.description))
            return
        }

        let version = release.version.description
        let stageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemController-Update-\(UUID().uuidString)", isDirectory: true)
        var keepStageForHelper = false
        defer {
            if !keepStageForHelper {
                try? FileManager.default.removeItem(at: stageDir)
            }
        }

        do {
            try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)
            setStatus(.downloading(version: version))

            let checksumData = try await downloadData(from: release.checksumURL)
            let checksumText = String(decoding: checksumData, as: UTF8.self)
            guard let expectedHash = ReleaseAssetInfo.expectedSHA256(for: release.zipName, in: checksumText) else {
                throw UpdateError.checksumMissing
            }

            let zipFile = stageDir.appendingPathComponent(release.zipName)
            try await downloadFile(from: release.zipURL, to: zipFile)

            let valid = try await Task.detached(priority: .utility) {
                try Self.sha256Hex(of: zipFile) == expectedHash
            }.value
            guard valid else {
                throw UpdateError.checksumMismatch
            }

            // Do not interrupt the user if they locked the screen while downloading.
            guard !isLocked() else {
                pendingRelease = release
                setStatus(.updateAvailable(version: version))
                return
            }

            setStatus(.installing(version: version))
            let unpackDir = stageDir.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)

            let stagedApp = try await Task.detached(priority: .userInitiated) {
                try Self.unpackAndVerify(zipURL: zipFile, into: unpackDir)
            }.value

            guard !isLocked() else {
                pendingRelease = release
                setStatus(.updateAvailable(version: version))
                return
            }

            let destination = Self.destinationAppURL()
            try Self.launchReplacementHelper(stagedApp: stagedApp, destination: destination, stageDir: stageDir)
            keepStageForHelper = true
            NSApp.terminate(nil)
        } catch {
            logger.error("Update install failed: \(error.localizedDescription, privacy: .public)")
            setStatus(.failed("Update failed: \(error.localizedDescription)"))
        }
    }

    private func setStatus(_ next: Status) {
        if status != next { status = next }
    }

    private func fetchLatestRelease() async throws -> ReleaseAssetInfo {
        let data = try await downloadData(from: Self.latestReleaseURL, headers: [
            "Accept": "application/vnd.github+json"
        ])
        guard let release = ReleaseAssetInfo.parseLatestRelease(from: data, repo: Self.repo) else {
            throw UpdateError.invalidReleaseMetadata
        }
        return release
    }

    private func downloadData(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("SystemController/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.httpFailure
        }
        return data
    }

    private func downloadFile(from url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        request.setValue("SystemController/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateError.httpFailure
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    nonisolated private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data? = try autoreleasepool {
                let data = try handle.read(upToCount: 65_536)
                guard let data, !data.isEmpty else { return nil }
                hasher.update(data: data)
                return data
            }
            if chunk == nil { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func unpackAndVerify(zipURL: URL, into unpackDir: URL) throws -> URL {
        try runTool("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, unpackDir.path])
        let appURL = unpackDir.appendingPathComponent("System Controller.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw UpdateError.missingAppBundle
        }
        try? runTool("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", appURL.path])
        try runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        return appURL
    }

    nonisolated private static func runTool(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.verificationFailed(executablePath)
        }
    }

    private static func destinationAppURL() -> URL {
        let fm = FileManager.default
        let currentBundle = Bundle.main.bundleURL
        if currentBundle.pathExtension == "app",
           fm.isWritableFile(atPath: currentBundle.deletingLastPathComponent().path) {
            return currentBundle
        }
        let systemApps = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if fm.isWritableFile(atPath: systemApps.path) {
            return systemApps.appendingPathComponent("System Controller.app", isDirectory: true)
        }
        return fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/System Controller.app", isDirectory: true)
    }

    private static func launchReplacementHelper(stagedApp: URL, destination: URL, stageDir: URL) throws {
        let script = """
        PID="$1"
        SRC="$2"
        DEST="$3"
        STAGE="$4"
        while /bin/kill -0 "$PID" 2>/dev/null; do
            /bin/sleep 0.2
        done
        /bin/mkdir -p "$(/usr/bin/dirname "$DEST")"
        /bin/rm -rf "$DEST"
        if /usr/bin/ditto "$SRC" "$DEST"; then
            /bin/rm -rf "$STAGE"
            /usr/bin/open "$DEST"
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            script,
            "system-controller-updater",
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            destination.path,
            stageDir.path
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private enum UpdateError: LocalizedError {
        case httpFailure
        case invalidReleaseMetadata
        case checksumMissing
        case checksumMismatch
        case missingAppBundle
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .httpFailure: "Could not reach GitHub Releases."
            case .invalidReleaseMetadata: "Release information could not be read."
            case .checksumMissing: "Release checksum was missing."
            case .checksumMismatch: "Downloaded update failed SHA-256 verification."
            case .missingAppBundle: "Update archive did not contain System Controller.app."
            case .verificationFailed: "Update failed code signature verification."
            }
        }
    }
}
