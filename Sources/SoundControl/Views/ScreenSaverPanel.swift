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
            VStack(alignment: .leading, spacing: 12) {
                SubpageHeader(title: "Screen Saver Settings") { isShowingSettings = false }
                ScreenSaverSettingsPage()
            }
        } else {
            mainPage
        }
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("SHOW").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            widgetToggle("Clock", systemImage: "clock", widget: .clock)
            widgetToggle("Calendar", systemImage: "calendar", widget: .calendar)
            widgetToggle("Claude usage", systemImage: "sparkle", widget: .claudeUsage)
            sessionsSection
            Picker(selection: Binding(get: { settings.mascot },
                                      set: { value in model.updateScreenSaver { $0.withMascot(value) } })) {
                ForEach(Mascot.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Mascot", systemImage: "pawprint")
            }

            Divider()
            Button {
                model.lockForOwner()
            } label: {
                Label("Start screen saver", systemImage: "touchid").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.keyboardLock.isLocked)
            if let problem = model.keyboardLock.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.warning)
                Button("Open Accessibility Settings") { PrivacySettings.openAccessibility() }
                    .font(.caption)
            }
            Text("Keys stay blocked and only your fingerprint or password gets you back in. Move the mouse to wake a dimmed screen.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                isShowingSettings = true
            } label: {
                Label("Dimming, clock, shortcut, pins…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "heart.circle.fill").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Smartheart Screen Saver").font(.headline)
                Text("\(settings.widgets.count) of \(ScreenSaverWidget.allCases.count) widgets on")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func widgetToggle(_ title: String, systemImage: String, widget: ScreenSaverWidget) -> some View {
        Toggle(isOn: Binding(get: { settings.shows(widget) },
                             set: { value in model.updateScreenSaver { $0.showing(widget, value) } })) {
            Label(title, systemImage: systemImage)
        }
    }

    /// Switch for the corner list and the corner it sits in.
    @ViewBuilder
    private var sessionsSection: some View {
        Toggle(isOn: Binding(get: { settings.showsSessions },
                             set: { value in model.updateScreenSaver { $0.withShowsSessions(value) } })) {
            Label("Claude sessions", systemImage: "terminal")
        }
        if settings.showsSessions {
            LabeledContent("Position") {
                CornerPicker(selection: settings.sessionsCorner,
                             onSelect: { corner in model.updateScreenSaver { $0.withSessionsCorner(corner) } })
            }
            Text("Sessions show as name chips; click one on the screen saver to watch it live.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
