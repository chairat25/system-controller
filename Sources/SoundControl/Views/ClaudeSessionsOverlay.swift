import SwiftUI
import SoundControlCore

/// A corner of the screen saver (the owner picks which): a card per Claude session that is working, with a green dot, the
/// session's topic and a terminal-style feed of what it is saying and doing right now.
/// A session that stops fades out, unless it is pinned. Click the header to pin or unpin it.
struct ClaudeSessionsOverlay: View {
    private static let fade = Animation.easeOut(duration: 1.2)
    /// Beyond this many cards the rest show only their header, so a busy Mac does not fill the screen.
    private static let feedCards = 3

    let monitor: ClaudeSessionMonitor
    let corner: ScreenSaverCorner
    let onPin: @MainActor (String, Bool) -> Void
    /// Pins made while the screen saver is up; the settings passed in are a snapshot taken when it started.
    @State private var pinned: [String]

    init(monitor: ClaudeSessionMonitor, corner: ScreenSaverCorner, pinned: [String], onPin: @escaping @MainActor (String, Bool) -> Void) {
        self.monitor = monitor
        self.corner = corner
        self.onPin = onPin
        _pinned = State(initialValue: pinned)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let rows = monitor.board.visible(pinned: pinned, now: context.date)
            VStack(alignment: corner.horizontalAlignment, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    SessionCard(row: row, lines: index < Self.feedCards ? monitor.activity[row.id] ?? [] : [],
                                screen: index < Self.feedCards ? monitor.screens[row.id] ?? [] : [],
                                showsFeed: index < Self.feedCards) { toggle(row) }
                        .frame(width: 520, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .animation(Self.fade, value: rows.map(\.id))
        }
        .onAppear { monitor.beginWatching() }
        .onDisappear { monitor.endWatching() }
    }

    private func toggle(_ row: ClaudeSessionBoard.Row) {
        let isPinned = !row.isPinned
        pinned = isPinned ? pinned + [row.id] : pinned.filter { $0 != row.id }
        onPin(row.id, isPinned)
    }
}

private struct SessionCard: View {
    let row: ClaudeSessionBoard.Row
    let lines: [TranscriptLine]
    /// The terminal's own text. When there is some it replaces the transcript feed, because it also shows the reply as it streams in.
    let screen: [String]
    let showsFeed: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if showsFeed, !screen.isEmpty {
                mirror
            } else if showsFeed, !lines.isEmpty || row.session.isWorking {
                feed
            }
        }
    }

    private var header: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                StatusDot(isWorking: row.session.isWorking)
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.session.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    if row.session.title != nil {
                        Text(row.session.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if row.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(row.isPinned ? "Unpin" : "Pin to keep it here")
    }

    /// The terminal's own lines, as they are on screen right now.
    private var mirror: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(screen.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11, weight: line.hasPrefix("❯") ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(Self.color(of: line))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Claude's progress line (`✽ Nesting… (45s …)`) is green, tool output dimmer, the rest white.
    private static func color(of line: String) -> Color {
        let trimmed = line.drop { $0 == " " }
        if let first = trimmed.first, "✻✽✶✢✳·".contains(first), trimmed.contains("…") { return Theme.working }
        if trimmed.hasPrefix("⎿") || trimmed.hasPrefix("⏺") { return .secondary }
        return .white
    }

    /// Looks like the terminal the session runs in: `❯` for what you typed, `●` for the reply, dimmer tool calls.
    private var feed: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(Self.glyph(line.kind) + line.text)
                    .font(.system(size: 11, weight: line.kind == .user ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(line.kind == .tool ? Color.secondary : Color.white)
                    .lineLimit(2)
            }
            if row.session.isWorking { WorkingLine() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static func glyph(_ kind: TranscriptLine.Kind) -> String {
        switch kind {
        case .user: "❯ "
        case .assistant: "● "
        case .tool: "⏺ "
        }
    }
}

/// The pulsing "✻ Working…" line under the feed while a reply is in progress.
private struct WorkingLine: View {
    @State private var isDim = false

    var body: some View {
        Text("✻ Working…")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.working)
            .opacity(isDim ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isDim = true }
            }
    }
}

/// Green while Claude works, grey once it has stopped.
private struct StatusDot: View {
    let isWorking: Bool

    var body: some View {
        Circle()
            .fill(isWorking ? Theme.working : Color.secondary.opacity(0.6))
            .frame(width: 9, height: 9)
            .shadow(color: isWorking ? Theme.working.opacity(0.8) : .clear, radius: 4)
            .animation(.easeOut(duration: 0.6), value: isWorking)
    }
}
