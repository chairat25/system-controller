import Foundation

public enum WallpaperKind: String, Codable, Sendable, CaseIterable {
    case screenSaver
    case desktop
}

/// Describes one wallpaper file. The bytes follow in a raw frame.
public struct WallpaperMeta: Codable, Sendable, Equatable {
    public static let maximumFileNameLength = 100

    public let kind: WallpaperKind
    /// Seconds since 1970 of the moment someone chose this wallpaper. The newest one wins everywhere.
    public let timestamp: Double
    public let fileName: String
    public let size: Int

    public init(kind: WallpaperKind, timestamp: Double, fileName: String, size: Int) {
        self.kind = kind
        self.timestamp = timestamp
        self.fileName = Self.cleanFileName(fileName)
        self.size = size
    }

    /// Keeps only the last path component and printable characters, so a name from the network cannot escape a folder.
    public static func cleanFileName(_ value: String) -> String {
        let last = value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let printable = String(String.UnicodeScalarView(last.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        })).trimmingCharacters(in: .whitespaces)
        let trimmed = printable.hasPrefix(".") ? String(printable.drop(while: { $0 == "." })) : printable
        return trimmed.isEmpty ? "wallpaper" : String(trimmed.suffix(maximumFileNameLength))
    }

    public var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }
}

/// Everything two Macs say to each other, as JSON inside message frames.
public enum SyncMessage: Codable, Sendable, Equatable {
    /// First message on a synced connection. The flags say what the sender wants to receive. `appVersion` and
    /// `platform` ("macos", "windows") are nil from 1.6.0 and older; they let each side warn about a mismatch.
    case hello(deviceID: String, name: String, wantsWallpaper: Bool, wantsRoaming: Bool,
               appVersion: String? = nil, platform: String? = nil)
    /// Pairing step 1 (initiator): a hash of its public key, sent before it sees the other key.
    case pairCommit(deviceID: String, name: String, commitment: Data)
    /// Pairing step 2 (responder): its public key.
    case pairKey(deviceID: String, name: String, publicKey: Data)
    /// Pairing step 3 (initiator): opens the commitment.
    case pairReveal(publicKey: Data)
    case pairConfirm
    case pairCancel
    /// "My wallpaper of this kind dates from this moment." The older side answers with `wallpaperRequest`.
    case wallpaperOffer(WallpaperMeta)
    case wallpaperRequest(kind: WallpaperKind, timestamp: Double)
    /// Header of a file; the next frame carries its bytes.
    case wallpaperData(WallpaperMeta)
    case roamingHandoff(RoamingObject)
    /// "I cannot take this one" (screen full, roaming just switched off): the sender puts it back on its own screen.
    /// Computers on 1.6.0 and older do not know this message and drop it.
    case roamingReturn(RoamingObject)

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> SyncMessage {
        try JSONDecoder().decode(SyncMessage.self, from: data)
    }
}
