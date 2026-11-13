import SwiftUI
import SoundControlCore

/// Screen Saver tab of the menu-bar popover: what the Smartheart Screen Saver shows. How it dims and the rest
/// sit one click away in `ScreenSaverSettingsPage`, so the tab stays short.
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
            PopoverSection("Widgets") {
                WidgetToggles(settings: settings, update: model.updateScreenSaver)
            }
            PopoverSection("Layout & Position") {
                SessionsCornerRow(settings: settings, update: model.updateScreenSaver)
                Footnote("Drag widgets on the screen saver to arrange and stack them.")
                WidgetLayoutResetButton(settings: settings, update: model.updateScreenSaver)
                    .font(.caption)
                if settings.showsSessions {
                    Footnote("Click a session chip on the screen saver to watch it live.")
                }
            }
            PopoverSection("Appearance") {
                SettingRow("Background", detail: settings.background.title, systemImage: "photo.on.rectangle") { EmptyView() }
                BackgroundControls(settings: settings,
                                   update: model.updateScreenSaver,
                                   onChoosePhoto: model.chooseScreenSaverBackgroundImage,
                                   onClearPhoto: model.clearScreenSaverBackgroundImage)
                Divider()
                MascotControls(settings: settings, update: model.updateScreenSaver)
            }
            activation
            PopoverSection("Advanced") {
                DisclosureRow(title: "More screen saver settings",
                              detail: "When the screen dims, what stays bright, and a key to start it",
                              systemImage: "slider.horizontal.3") { isShowingSettings = true }
            }
        }
    }

    private var overview: some View {
        let isActive = model.keyboardLock.lock?.unlock == .ownerAuthentication
        return HStack(spacing: Spacing.control) {
            Image(systemName: "heart.circle.fill").font(.title).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smartheart Screen Saver").font(.headline)
                Text("\(settings.widgets.count + (settings.showsSessions ? 1 : 0)) of \(ScreenSaverWidget.allCases.count + 1) widgets on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.related)
            StatusIndicator(text: isActive ? "Running" : "Off", level: isActive ? .good : .off)
        }
    }

    private var activation: some View {
        PopoverSection("Activation & Protection") {
            PrimaryActionButton(title: "Start screen saver", systemImage: "play.fill",
                                isDisabled: model.keyboardLock.isLocked) { model.lockForOwner() }
            if let problem = model.keyboardLock.problem {
                Footnote(problem, tone: Theme.warning)
                Button("Open Accessibility Settings") { PrivacySettings.openAccessibility() }
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: Spacing.related) {
                hint("keyboard", "Keys stay blocked while it runs.")
                hint("touchid", "Unlock with your fingerprint or password.")
                hint("cursorarrow.motionlines", "Move the mouse to wake a dimmed screen.")
                hint("hand.draw", "Swipe two fingers left or right on it to change settings live.")
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
