import SwiftUI
import SoundControlCore

struct TriggersPage: View {
    enum Filter: String, CaseIterable {
        case all = "All", on = "On", off = "Off"
    }

    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter = Filter.all
    @State private var editing: TriggerID?
    @State private var collapsed: Set<TriggerCategory> = []

    var body: some View {
        WindowPage {
            PageHeader(title: "Triggers",
                       subtitle: "Every moment on your Mac can make a sound. Pick one, or let your pack decide.") {
                actions
            }
            toolbar
            ForEach(TriggerCategory.allCases, id: \.self) { category in
                let rows = visibleTriggers(in: category)
                if !rows.isEmpty {
                    section(category, rows: rows)
                }
            }
            if TriggerCategory.allCases.allSatisfy({ visibleTriggers(in: $0).isEmpty }) {
                EmptyState("No matching triggers", message: "Try another word or switch the filter back to All.",
                           systemImage: "magnifyingglass") {
                    Button("Show all triggers") {
                        search = ""
                        filter = .all
                    }
                }
            }
        }
        .sheet(item: $editing) { trigger in
            TriggerDetailSheet(trigger: trigger)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                model.update { $0.withRecommendedEnabled() }
            } label: {
                Label("Turn on recommended", systemImage: "wand.and.stars")
            }
            Menu {
                Button("Turn everything on") { model.update { $0.withAllTriggers(enabled: true) } }
                Button("Turn everything off") { model.update { $0.withAllTriggers(enabled: false) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
            .accessibilityLabel("More actions")
        }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.control) { toolbarItems }
            VStack(alignment: .leading, spacing: Spacing.related) { toolbarItems }
        }
    }

    @ViewBuilder
    private var toolbarItems: some View {
        SearchField(prompt: "Search triggers", text: $search)
        FilterSegment(title: "Show", selection: $filter)
        Spacer(minLength: 0)
        Text("\(model.config.enabledTriggers.count) of \(TriggerID.allCases.count) on")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func section(_ category: TriggerCategory, rows: [TriggerInfo]) -> some View {
        let all = TriggerCatalog.triggers(in: category)
        let onCount = all.filter { model.config.isEnabled($0.id) }.count
        let isCollapsed = collapsed.contains(category) && search.isEmpty
        return VStack(alignment: .leading, spacing: Spacing.related) {
            ListSectionHeader(category.title, count: "\(onCount) of \(all.count) on") {
                Button(onCount == all.count ? "Turn all off" : "Turn all on") {
                    model.update { $0.withAllTriggers(enabled: onCount != all.count, in: category) }
                }
                .buttonStyle(.link)
                .font(.caption)
                RowIconButton(systemImage: isCollapsed ? "chevron.right" : "chevron.down",
                              help: isCollapsed ? "Show \(category.title)" : "Hide \(category.title)") {
                    withAnimation(.easeInOut(duration: 0.15)) { toggle(category) }
                }
            }
            if !isCollapsed {
                GroupedList(items: rows) { info in
                    TriggerRow(info: info) { editing = info.id }
                }
            }
        }
    }

    private func toggle(_ category: TriggerCategory) {
        if collapsed.contains(category) { collapsed.remove(category) } else { collapsed.insert(category) }
    }

    private func visibleTriggers(in category: TriggerCategory) -> [TriggerInfo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return TriggerCatalog.triggers(in: category).filter { info in
            let matchesSearch = query.isEmpty || info.title.lowercased().contains(query)
                || info.detail.lowercased().contains(query) || category.title.lowercased().contains(query)
            let isOn = model.config.isEnabled(info.id)
            let matchesFilter = filter == .all || (filter == .on && isOn) || (filter == .off && !isOn)
            return matchesSearch && matchesFilter
        }
    }
}

extension TriggerID: Identifiable {
    public var id: String { rawValue }
}

struct TriggerRow: View {
    @Environment(AppModel.self) private var model
    let info: TriggerInfo
    let onEdit: () -> Void

    var body: some View {
        let isOn = model.config.isEnabled(info.id)
        HStack(spacing: Spacing.control) {
            SymbolTile(symbol: info.symbol, isActive: isOn)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(info.title).font(.body.weight(.medium)).foregroundStyle(isOn ? .primary : .secondary)
                    if info.isRecommended { Badge(text: "Recommended", color: Theme.accent) }
                    if info.permission == .inputMonitoring { Badge(text: "Input Monitoring", symbol: "hand.raised.fill") }
                    if info.permission == .bluetooth { Badge(text: "Bluetooth", symbol: "hand.raised.fill") }
                }
                HStack(spacing: 6) {
                    Text(info.detail)
                    Text("·")
                    Text(SoundResolver.sourceDescription(for: info.id, in: model.config))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if isOn, let tweak = MacSoundTweak.soundTweak(overlapping: info.id) {
                    if model.config.isApplied(tweak) {
                        Label("Replaces the macOS \(tweak.title.lowercased())", systemImage: "speaker.slash")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.bubble")
                            Text("macOS plays its own sound here too.")
                            Button("Replace it") { model.update { $0.withReplaceMacSounds(true) } }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                if let reason = model.unavailable[info.id], isOn {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer(minLength: Spacing.related)
            PlayButton { model.preview(info.id) }
            TriggerSoundMenu(trigger: info.id)
            RowIconButton(systemImage: "slider.horizontal.3", help: "Sounds, volume and rotation", action: onEdit)
            Toggle(info.title, isOn: Binding(get: { isOn }, set: { model.setTrigger(info.id, enabled: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .rowPadding()
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}
