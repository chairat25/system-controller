import Foundation

public enum SyncFrameKind: UInt8, Sendable {
    /// A JSON `SyncMessage`.
    case message = 0
    /// File bytes that belong to the `wallpaperData` message before it.
    case raw = 1
}

public struct SyncFrame: Sendable, Equatable {
    public let kind: SyncFrameKind
    public let payload: Data
}

public enum SyncFrameError: Error, Equatable {
    case unknownKind
    case tooLarge
}

/// Length-prefixed framing: 4 bytes of payload length (big endian), 1 byte of kind, then the payload.
public enum SyncFraming {
    public static let headerSize = 5
    public static let maximumMessageBytes = 64 * 1024
    public static let maximumRawBytes = WallpaperSyncPolicy.maximumBytes

    public static func maximumBytes(for kind: SyncFrameKind) -> Int {
        kind == .message ? maximumMessageBytes : maximumRawBytes
    }

    public static func header(kind: SyncFrameKind, length: Int) -> Data {
        let value = UInt32(clamping: length)
        return Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF),
                     UInt8(value & 0xFF), kind.rawValue])
    }

    public static func encode(kind: SyncFrameKind, payload: Data) -> Data {
        header(kind: kind, length: payload.count) + payload
    }
}

/// Collects incoming bytes and returns each complete frame. A bad or oversized header is an error: close the connection.
public struct SyncFrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [SyncFrame] {
        buffer.append(bytes)
        var frames: [SyncFrame] = []
        while buffer.count >= SyncFraming.headerSize {
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
            guard let kind = SyncFrameKind(rawValue: buffer[start + 4]) else { throw SyncFrameError.unknownKind }
            guard length <= SyncFraming.maximumBytes(for: kind) else { throw SyncFrameError.tooLarge }
            let total = SyncFraming.headerSize + length
            guard buffer.count >= total else { break }
            let payload = Data(buffer[start + SyncFraming.headerSize..<start + total])
            frames.append(SyncFrame(kind: kind, payload: payload))
            buffer = Data(buffer[(start + total)...])
        }
        return frames
    }
}
