import AppKit
import SwiftUI
import SoundControlCore

enum Page: String, CaseIterable, Identifiable {
    case triggers = "Triggers", packs = "Sound Packs", sounds = "My Sounds", activity = "Activity", settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .triggers: "bolt.horizontal.fill"
        case .packs: "square.stack.3d.up.fill"
        case .sounds: "waveform"
        case .activity: "list.bullet.rectangle"
        case .settings: "gearshape.fill"
        }
    }
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var page: Page? = .triggers

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(minWidth: 620)
                .overlay(alignment: .bottom) { alertBanner }
        }
        .tint(Theme.accent)
        .frame(minWidth: 860, minHeight: 560)
        // Show in the Dock and app switcher only while the window is open.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill").font(.title).foregroundStyle(Theme.accent)
                Text("Sound Control").font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            List(Page.allCases, selection: $page) { page in
                Label(page.rawValue, systemImage: page.symbol)
                    .badge(page == .triggers ? model.config.enabledTriggers.count : 0)
                    .tag(page)
            }
            .listStyle(.sidebar)
            listeningCard
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    private var listeningCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                StatusIndicator(text: model.config.isListening ? "Listening" : "Paused",
                                level: model.config.isListening ? .good : .off)
                Label(SoundResolver.packName(model.config.activePack, in: model.config), systemImage: "square.stack.3d.up")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("Listening", isOn: Binding(get: { model.config.isListening },
                                     set: { value in model.update { $0.withListening(value) } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(Spacing.control)
        .background(Theme.groupFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous).strokeBorder(Theme.hairline))
        .padding(10)
    }

    @ViewBuilder
    private var detail: some View {
        switch page ?? .triggers {
        case .triggers: TriggersPage()
        case .packs: PacksPage()
        case .sounds: MySoundsPage()
        case .activity: ActivityPage()
        case .settings: SettingsPage()
        }
    }

    @ViewBuilder
    private var alertBanner: some View {
        if let message = model.alertMessage {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(message).font(.callout).textSelection(.enabled)
                Spacer()
                Button { model.alertMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
