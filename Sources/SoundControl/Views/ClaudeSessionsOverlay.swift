import SwiftUI
import SoundControlCore

/// A corner of the screen saver (the owner picks which): a name chip per Claude session that is working, with a green dot.
/// Many sessions stay small this way; click a chip to open its live terminal view, click again to fold it.
/// A session that stops fades out, unless it is pinned with the pin button.
struct ClaudeSessionsOverlay: View {
    private static let fade = Animation.easeOut(duration: 1.2)
    private static let feedWidth: CGFloat = 520

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
                ForEach(rows) { row in
                    let isExpanded = monitor.expanded.contains(row.id)
                    SessionCard(row: row, isExpanded: isExpanded,
                                lines: isExpanded ? monitor.activity[row.id] ?? [] : [],
                                screen: isExpanded ? monitor.screens[row.id] ?? [] : [],
                                alignment: corner.horizontalAlignment,
                                onToggle: { monitor.toggleExpanded(row.id) },
                                onPin: { togglePin(row) })
                        .frame(width: isExpanded ? Self.feedWidth : nil,
                               alignment: corner.isLeft ? .leading : .trailing)
                        .transition(.opacity)
                }
            }
            .animation(Self.fade, value: rows.map(\.id))
            .animation(.easeOut(duration: 0.25), value: monitor.expanded)
        }
        .onAppear { monitor.beginWatching() }
        .onDisappear { monitor.endWatching() }
    }

    private func togglePin(_ row: ClaudeSessionBoard.Row) {
        let isPinned = !row.isPinned
        pinned = isPinned ? pinned + [row.id] : pinned.filter { $0 != row.id }
        onPin(row.id, isPinned)
    }
}

private struct SessionCard: View {
    let row: ClaudeSessionBoard.Row
    let isExpanded: Bool
    let lines: [TranscriptLine]
    /// The terminal's own text. When there is some it replaces the transcript feed, because it also shows the reply as it streams in.
    let screen: [String]
    let alignment: HorizontalAlignment
    let onToggle: () -> Void
    let onPin: () -> Void

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            chip
            if isExpanded, !screen.isEmpty {
                mirror
            } else if isExpanded {
                feed
            }
        }
    }

    private var chip: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    StatusDot(isWorking: row.session.isWorking)
                    Text(isExpanded ? row.session.displayName : Self.short(row.session.displayName))
                        .font(.callout.weight(.medium)).lineLimit(1)
                    if isExpanded, row.session.title != nil {
                        Text(row.session.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Fold" : "Watch it live")
            Button(action: onPin) {
                Image(systemName: row.isPinned ? "pin.fill" : "pin")
                    .font(.caption2)
                    .foregroundStyle(row.isPinned ? .white : .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.isPinned ? "Unpin" : "Pin to keep it here")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .fixedSize(horizontal: !isExpanded, vertical: false)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    /// A folded chip sizes to its name, so a long topic is cut to keep the chips small.
    private static let chipNameLength = 40

    private static func short(_ name: String) -> String {
        name.count <= chipNameLength ? name : String(name.prefix(chipNameLength - 1)) + "…"
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
            if lines.isEmpty, !row.session.isWorking {
                Text("Nothing new yet").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
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
