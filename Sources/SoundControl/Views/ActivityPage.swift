import SwiftUI
import SoundControlCore

struct ActivityPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ActivityFilter.all
    @State private var search = ""

    var body: some View {
        WindowPage {
            PageHeader(title: "Activity",
                       subtitle: "What your Mac did and what it sounded like. Keys, clicks and volume ticks are not logged.") {
                Text("\(model.log.playCount(since: Calendar.current.startOfDay(for: Date()))) played today")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if model.log.entries.isEmpty {
                EmptyState("No sound activity yet",
                           message: "Events appear here as they happen. Plug in your charger or lock the screen to see one.",
                           systemImage: "waveform.path")
            } else {
                toolbar
                timeline
            }
        }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.control) {
                SearchField(prompt: "Search events or sounds", text: $search)
                FilterSegment(title: "Show", selection: $filter)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Spacing.related) {
                SearchField(prompt: "Search events or sounds", text: $search)
                FilterSegment(title: "Show", selection: $filter)
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        let groups = ActivityTimeline.groups(visibleEntries, now: Date(), calendar: .current)
        if groups.isEmpty {
            EmptyState("No matching events", message: "Try another word or switch the filter back to All.",
                       systemImage: "magnifyingglass") {
                Button("Show all events") {
                    search = ""
                    filter = .all
                }
            }
        } else {
            ForEach(groups, id: \.day) { group in
                VStack(alignment: .leading, spacing: Spacing.related) {
                    ListSectionHeader(group.day.rawValue, count: "\(group.entries.count)")
                    GroupedList(items: group.entries) { entry in ActivityRow(entry: entry) }
                }
            }
        }
    }

    private var visibleEntries: [ActivityEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.log.entries.filter { entry in
            guard filter.matches(entry) else { return false }
            guard !query.isEmpty else { return true }
            let text = [TriggerCatalog.info(for: entry.trigger).title, entry.soundName ?? "", entry.context ?? ""]
            return text.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry
    var compact = false

    var body: some View {
        let info = TriggerCatalog.info(for: entry.trigger)
        HStack(spacing: 12) {
            SymbolTile(symbol: info.symbol, isActive: entry.didPlay, size: compact ? 24 : Theme.tileSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(compact ? .callout : .body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !entry.didPlay {
                Badge(text: "Skipped", symbol: "forward.end")
            }
            Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 0 : 14)
        .padding(.vertical, compact ? 3 : 9)
    }

    private var subtitle: String {
        let outcome = entry.skipReason.map(\.rawValue) ?? "♪ \(entry.soundName ?? "Sound")"
        guard let context = entry.context, !context.isEmpty else { return outcome }
        return "\(context) · \(outcome)"
    }
}
