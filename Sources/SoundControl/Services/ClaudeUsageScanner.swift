import Foundation
import SoundControlCore

/// Sums Claude Code usage from the transcripts in `~/.claude/projects`.
/// Each call reads only the bytes added since the last call, so a refresh every few seconds stays cheap.
actor ClaudeUsageScanner {
    static let shared = ClaudeUsageScanner()

    private static let minimumLookback: TimeInterval = 12 * 3600
    private static let usageMarker = Data(#""usage""#.utf8)
    private static let newline = UInt8(ascii: "\n")
    private static let chunkSize = 8 * 1024 * 1024

    private let root = ClaudePaths.projects
    /// Bytes of each transcript already consumed, always ending on a line boundary.
    private var offsets: [URL: UInt64] = [:]
    private var entries: [String: TokenUsageEntry] = [:]

    func summary(now: Date = Date()) -> ClaudeUsageSummary {
        let cutoff = cutoff(now: now)
        for file in transcripts(modifiedAfter: cutoff) { read(file, since: cutoff) }
        entries = entries.filter { $0.value.date >= cutoff }
        return ClaudeUsage.summary(of: Array(entries.values), now: now)
    }

    /// Far enough back to cover the whole of today and any five-hour window that is still open.
    private func cutoff(now: Date) -> Date {
        min(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-Self.minimumLookback))
    }

    private func transcripts(modifiedAfter cutoff: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        return walker.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= cutoff
            else { return nil }
            return url
        }
    }

    /// Reads in chunks so one huge transcript never has to sit in memory whole.
    private func read(_ file: URL, since cutoff: Date) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var offset = offsets[file] ?? 0
        if size < offset { offset = 0 }
        while offset < size {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let chunk = try? handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }
            guard let lastNewline = chunk.lastIndex(of: Self.newline) else {
                // A line longer than a chunk (inline images) holds no usage worth waiting for; step past it.
                // A short tail without a newline is a line still being written, so wait for the rest.
                guard chunk.count == Self.chunkSize else { break }
                offset += UInt64(chunk.count)
                offsets[file] = offset
                continue
            }
            let complete = chunk[chunk.startIndex...lastNewline]
            collect(complete, since: cutoff)
            offset += UInt64(complete.count)
            offsets[file] = offset
        }
    }

    private func collect(_ lines: Data, since cutoff: Date) {
        for line in lines.split(separator: Self.newline) where line.range(of: Self.usageMarker) != nil {
            guard let entry = ClaudeUsage.entry(fromLine: Data(line)), entry.date >= cutoff else { continue }
            entries[entry.id] = entry
        }
    }
}
