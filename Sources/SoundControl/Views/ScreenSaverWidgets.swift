import SwiftUI
import SoundControlCore

/// Shared translucent dark glass surface for widgets: keeps the topmost widget sharp while allowing
/// any overlapped widget underneath to remain faintly visible (~30% bleed-through).
struct WidgetGlassBackdrop: ViewModifier {
    let showCard: Bool
    let isDragging: Bool
    let isOverlappingLower: Bool
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if showCard {
                    ZStack {
                        shape.fill(Color.black.opacity(0.68))
                        shape.fill(Color.white.opacity(isDragging ? 0.11 : (isOverlappingLower ? 0.08 : 0.06)))
                    }
                    .overlay(
                        shape.strokeBorder(
                            Color.white.opacity(isDragging ? 0.38 : (isOverlappingLower ? 0.22 : 0.09)),
                            lineWidth: 1
                        )
                    )
                    .shadow(
                        color: .black.opacity(isDragging ? 0.65 : (isOverlappingLower ? 0.48 : 0.18)),
                        radius: isDragging ? 20 : (isOverlappingLower ? 14 : 8),
                        y: isDragging ? 10 : 4
                    )
                }
            }
            .animation(.easeOut(duration: 0.18), value: showCard)
            .animation(.easeOut(duration: 0.18), value: isDragging)
            .animation(.easeOut(duration: 0.18), value: isOverlappingLower)
    }
}

extension View {
    func widgetGlassBackdrop(
        showCard: Bool = true,
        isDragging: Bool = false,
        isOverlappingLower: Bool = false,
        cornerRadius: CGFloat = 18
    ) -> some View {
        modifier(WidgetGlassBackdrop(
            showCard: showCard,
            isDragging: isDragging,
            isOverlappingLower: isOverlappingLower,
            cornerRadius: cornerRadius
        ))
    }
}

/// Time and date, large.
struct ClockWidget: View {
    var isDragging: Bool = false
    var isOverlappingLower: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 128, weight: .thin).monospacedDigit())
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .widgetGlassBackdrop(
                showCard: isDragging || isOverlappingLower,
                isDragging: isDragging,
                isOverlappingLower: isOverlappingLower,
                cornerRadius: 22
            )
        }
    }
}

/// The current month with today highlighted.
struct CalendarWidget: View {
    var isDragging: Bool = false
    var isOverlappingLower: Bool = false
    private static let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 7)
    private static let calendar = Calendar.current

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            WidgetCard(title: context.date.formatted(.dateTime.month(.wide).year()),
                       symbol: "calendar",
                       isDragging: isDragging,
                       isOverlappingLower: isOverlappingLower) {
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                        Text(initial).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(Self.cells(for: context.date).enumerated()), id: \.offset) { _, day in
                        dayCell(day, today: Self.calendar.component(.day, from: context.date))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int?, today: Int) -> some View {
        if let day {
            Text("\(day)")
                .font(.callout.monospacedDigit().weight(day == today ? .bold : .regular))
                .frame(width: 30, height: 30)
                .background(day == today ? Theme.accent : .clear, in: Circle())
        } else {
            Color.clear.frame(width: 30, height: 30)
        }
    }

    private static var weekdayInitials: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Blank cells before the 1st, then the day numbers of the month.
    private static func cells(for date: Date) -> [Int?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let blanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: blanks) + days.map { Optional($0) }
    }
}

/// Claude Code token usage for the current five-hour window and for today, read from local transcripts.
struct ClaudeUsageWidget: View {
    var isDragging: Bool = false
    var isOverlappingLower: Bool = false
    private static let refreshInterval: Duration = .seconds(30)
    @State private var summary = ClaudeUsageSummary.empty
    @State private var hasLoaded = false

    var body: some View {
        WidgetCard(title: "Claude usage", symbol: "sparkle", isDragging: isDragging, isOverlappingLower: isOverlappingLower) {
            VStack(alignment: .leading, spacing: 14) {
                usageRow(title: "This 5-hour window", tokens: summary.windowTokens, replies: summary.windowReplies,
                         note: windowNote)
                usageRow(title: "Today", tokens: summary.todayTokens, replies: summary.todayReplies, note: nil)
            }
            .frame(width: 230, alignment: .leading)
            .redacted(reason: hasLoaded ? [] : .placeholder)
        }
        .task {
            while !Task.isCancelled {
                summary = await ClaudeUsageScanner.shared.summary()
                hasLoaded = true
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    private var windowNote: Text? {
        summary.windowResetsAt.map { Text("resets \($0, format: .dateTime.hour().minute())") }
    }

    private func usageRow(title: String, tokens: Int, replies: Int, note: Text?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ClaudeUsageSummary.format(tokens: tokens)).font(.title.weight(.semibold).monospacedDigit())
                Text("tokens · \(replies) replies").font(.caption).foregroundStyle(.secondary)
            }
            if let note { note.font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Rounded card with a title, shared by the screen saver widgets.
private struct WidgetCard<Content: View>: View {
    let title: String
    let symbol: String
    var isDragging: Bool = false
    var isOverlappingLower: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(Theme.accent)
            content
        }
        .padding(20)
        .widgetGlassBackdrop(showCard: true, isDragging: isDragging, isOverlappingLower: isOverlappingLower)
    }
}
