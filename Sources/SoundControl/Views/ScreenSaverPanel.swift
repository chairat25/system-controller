import SwiftUI
import SoundControlCore

/// Screen Saver tab of the menu-bar popover: its status and the start button. Every setting sits one click away
/// in `ScreenSaverSettingsPage`, so the tab stays short.
struct ScreenSaverPanel: View {
    @Environment(AppModel.self) private var model

    private var settings: ScreenSaverSettings { model.screenSaver }

    @State private var isShowingSettings = false

    var body: some View {
        if isShowingSettings {
            VStack(alignment: .leading, spacing: Spacing.control) {
                SubpageHeader(title: "Screen Saver Settings") { isShowingSettings = false }
                ScreenSaverSettingsPage()
            }
        } else {
            mainPage
        }
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            overview
            activation
            DisclosureCard(title: "Screen Saver Settings",
                           detail: "Widgets, background, mascot, dimming and the start key",
                           systemImage: "slider.horizontal.3") { isShowingSettings = true }
        }
    }

    private var overview: some View {
        let isActive = model.keyboardLock.lock?.unlock == .ownerAuthentication
        return HStack(spacing: Spacing.control) {
            SymbolTile(symbol: "heart.fill", isActive: isActive, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Smartheart Screen Saver")).font(.headline)
                Text(L("%@ of %@ widgets on", settings.widgets.count + (settings.showsSessions ? 1 : 0), ScreenSaverWidget.allCases.count + 1))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.related)
            StatusIndicator(text: isActive ? "Running" : "Off", level: isActive ? .good : .off)
        }
    }

    private var activation: some View {
        PopoverSection(L("Activation & Protection")) {
            PrimaryActionButton(title: "Start screen saver", systemImage: "play.fill",
                                isDisabled: model.keyboardLock.isLocked) { model.lockForOwner() }
            if let problem = model.keyboardLock.problem {
                Footnote(problem, tone: Theme.warning)
                Button(L("Open Accessibility Settings")) { PrivacySettings.openAccessibility() }
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: Spacing.related) {
                hint("keyboard", "Keys stay blocked while it runs.")
                hint("touchid", "Unlock with your fingerprint or password.")
                hint("cursorarrow.motionlines", "Move the mouse to wake a dimmed screen.")
                hint("hand.draw", "Swipe two fingers to adjust settings live.")
            }
        }
    }

    private func hint(_ systemImage: String, _ text: String) -> some View {
        Label {
            Footnote(text)
        } icon: {
            Image(systemName: systemImage).font(.caption).foregroundStyle(.secondary).frame(width: Theme.rowIconWidth)
        }
    }
}
