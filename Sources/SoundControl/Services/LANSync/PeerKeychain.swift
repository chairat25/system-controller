import Foundation

/// Stores the key shared with each paired Mac in a file readable only by this user (0600),
/// one file per peer id. A file instead of the Keychain: the ad-hoc signed app is re-signed on
/// every build, and the Keychain would ask for access again each time. Sync is meant for a home network.
enum PeerKeychain {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SystemController/PeerKeys", isDirectory: true)
    }

    /// Peer ids come from the network, so only a safe file-name form is used.
    private static func fileURL(_ peerID: String) -> URL {
        let safe = peerID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }
        return folder.appendingPathComponent(safe.joined() + ".key")
    }

    static func save(_ key: Data, for peerID: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let url = fileURL(peerID)
        try key.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(_ peerID: String) -> Data? {
        try? Data(contentsOf: fileURL(peerID))
    }

    static func delete(_ peerID: String) {
        try? FileManager.default.removeItem(at: fileURL(peerID))
    }
}
