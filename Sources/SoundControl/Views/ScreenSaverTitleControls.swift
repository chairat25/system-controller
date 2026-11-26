import SwiftUI
import SoundControlCore

/// Title line on top of the screen saver: show or hide it, type a new one, or pick a suggestion.
/// `allowsTyping` is false on the screen saver itself, where the keyboard is locked.
struct TitleControls: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate
    var allowsTyping = true

    @State private var draft = ""
    @FocusState private var isEditing: Bool

    private static let systemTitles = TitleSuggestions.systemTitles(
        fullName: NSFullUserName(), computerName: Host.current().localizedName ?? "")

    private var suggestions: [String] {
        TitleSuggestions.suggestions(for: allowsTyping ? draft : "", recent: settings.recentTitles,
                                     system: Self.systemTitles)
            .filter { $0 != settings.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Show title"), isOn: Binding(get: { settings.showsTitle },
                                               set: { value in update { $0.withShowsTitle(value) } }))
            Group {
                if allowsTyping {
                    TextField(L("Title"), text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEditing)
                        .onSubmit(commit)
                        .onChange(of: isEditing) { _, editing in if !editing { commit() } }
                } else {
                    Text(L(settings.title)).font(.callout).lineLimit(1)
                }
                if !suggestions.isEmpty {
                    FlowChips(items: suggestions) { choice in
                        draft = choice
                        update { $0.withTitle(choice) }
                    }
                }
            }
            .disabled(!settings.showsTitle)
            .opacity(settings.showsTitle ? 1 : 0.5)
        }
        .onAppear { draft = settings.title }
    }

    private func commit() {
        guard draft != settings.title else { return }
        update { $0.withTitle(draft) }
    }
}

/// Suggestion buttons that wrap onto new lines.
private struct FlowChips: View {
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Button { onPick(item) } label: {
                Text(item).font(.caption).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassChip(isSelected: false, radius: 12)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One size slider per widget that is on, the same sizes a pinch or the corner handle sets.
struct WidgetSizeControls: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate

    private var items: [(ScreenSaverItem, String)] {
        [(.clock, "Clock"), (.calendar, "Calendar"), (.claudeUsage, "Claude usage"), (.sessions, "Claude sessions")]
            .filter { item, _ in
                switch item {
                case .clock: settings.shows(.clock)
                case .calendar: settings.shows(.calendar)
                case .claudeUsage: settings.shows(.claudeUsage)
                case .sessions: settings.showsSessions
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item, title in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(title, value: "\(Int((settings.scale(of: item) * 100).rounded()))%")
                    Slider(value: Binding(get: { settings.scale(of: item) },
                                          set: { value in update { $0.scaling(item, to: value) } }),
                           in: ScreenSaverSettings.scaleRange)
                }
            }
            Text(L("Pinch a widget or drag its corner on the screen saver to resize it."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
