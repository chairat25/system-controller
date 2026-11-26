import SwiftUI
import SoundControlCore

struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Settings", subtitle: "How Sound Control listens, plays and fits in with macOS.") { EmptyView() }
                .padding([.horizontal, .top], WindowLayout.pagePadding)
            form
        }
    }

    private var form: some View {
        Form {
            Section(L("General")) {
                Toggle(L("Listening"), isOn: Binding(get: { model.config.isListening },
                                                  set: { value in model.update { $0.withListening(value) } }))
                LabeledContent(L("Master volume")) {
                    HStack {
                        Slider(value: Binding(get: { model.config.masterVolume },
                                              set: { value in model.update { $0.withMasterVolume(value) } }), in: 0...1)
                        PlayButton { model.preview(.chargerConnected) }
                    }
                }
                Toggle(L("Launch at login"), isOn: Binding(get: { model.isLaunchAtLoginEnabled },
                                                        set: { model.setLaunchAtLogin($0) }))
            }

            Section {
                Toggle(L("Instant sounds"), isOn: Binding(get: { model.config.keepAudioReady },
                                                       set: { value in model.update { $0.withKeepAudioReady(value) } }))
                Toggle(L("One sound per moment"), isOn: Binding(get: { model.config.avoidOverlap },
                                                             set: { value in model.update { $0.withAvoidOverlap(value) } }))
            } header: {
                Text(L("Audio Behavior"))
            } footer: {
                Text(L("Instant sounds keeps the audio output ready while you use the Mac and lets it rest when you step away, so the Mac still sleeps on its own. One sound per moment plays only the first of several events that happen together, such as wake + display on."))
            }

            Section {
                Toggle(isOn: Binding(get: { model.config.replaceMacSounds },
                                     set: { value in model.update { $0.withReplaceMacSounds(value) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Replace macOS sounds"))
                        Text(L("When a trigger is on, macOS's own sound for that moment is muted so only yours plays."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(MacSoundTweak.allCases.filter(\.isSound), id: \.self) { tweak in
                    LabeledContent {
                        Badge(text: model.config.isApplied(tweak) ? "Muted by Sound Control" : "macOS default",
                              color: model.config.isApplied(tweak) ? Theme.accent : .secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L(tweak.title))
                            Text(L(tweak.detail)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Toggle(isOn: Binding(get: { model.config.hideScreenshotThumbnail },
                                     set: { value in model.update { $0.withHideScreenshotThumbnail(value) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Hide floating screenshot thumbnail"))
                        Text(L(MacSoundTweak.screenshotThumbnail.detail)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L("macOS Integration"))
            } footer: {
                Text(L("macOS gets its sounds back when you turn the trigger off, pause listening, or quit Sound Control. Interface sound effects may need a log out to fully apply."))
            }

            Section {
                Toggle(L("Quiet hours"), isOn: quietBinding(\.isEnabled))
                DatePicker(L("From"), selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    .disabled(!model.config.quietHours.isEnabled)
                DatePicker(L("Until"), selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    .disabled(!model.config.quietHours.isEnabled)
            } header: {
                Text(L("Quiet Hours"))
            } footer: {
                Text(L("Nothing plays during this window. It may cross midnight."))
            }

            Section(L("Screen Saver")) {
                LabeledContent(L("Background")) {
                    Text(L(model.screenSaver.background.title)).foregroundStyle(.secondary)
                }
                BackgroundControls(settings: model.screenSaver,
                                   update: model.updateScreenSaver,
                                   onChoosePhoto: model.chooseScreenSaverBackgroundImage,
                                   onClearPhoto: model.clearScreenSaverBackgroundImage)
                Toggle(L("Hide mascot"), isOn: Binding(
                    get: { model.screenSaver.activeMascot == .none },
                    set: { isHidden in model.updateScreenSaver { $0.withMascotHidden(isHidden) } }
                ))
                LabeledContent(L("Mascot")) {
                    Text(L(model.screenSaver.activeMascot.title)).foregroundStyle(.secondary)
                }
                MascotGrid(selection: model.screenSaver.activeMascot) { mascot in
                    model.updateScreenSaver { $0.withMascot(mascot) }
                }
                .opacity(model.screenSaver.activeMascot == .none ? 0.55 : 1)
                WidgetLayoutResetButton(settings: model.screenSaver, update: model.updateScreenSaver)
            }

            LANSyncSection()

            Section(L("Thresholds")) {
                Stepper("Battery low at \(model.config.batteryLowPercent)%", value: Binding(
                    get: { model.config.batteryLowPercent },
                    set: { value in model.update { $0.withBatteryThresholds(low: value, critical: $0.batteryCriticalPercent) } }
                ), in: AppConfig.batteryLowRange)
                Stepper("Battery critical at \(model.config.batteryCriticalPercent)%", value: Binding(
                    get: { model.config.batteryCriticalPercent },
                    set: { value in model.update { $0.withBatteryThresholds(low: $0.batteryLowPercent, critical: value) } }
                ), in: AppConfig.batteryCriticalRange)
                Stepper("Away after \(model.config.idleMinutes) min without input", value: Binding(
                    get: { model.config.idleMinutes },
                    set: { value in model.update { $0.withIdleMinutes(value) } }
                ), in: AppConfig.idleMinutesRange)
            }

            Section {
                LabeledContent(L("Input Monitoring")) {
                    HStack {
                        Badge(text: model.hasInputPermission ? "Granted" : "Not granted",
                              color: model.hasInputPermission ? .green : Theme.warning)
                        Button(L("Open Settings")) { PrivacySettings.openInputMonitoring() }
                        Button(L("Recheck")) { model.recheckInputPermission() }
                    }
                }
                LabeledContent(L("Accessibility (keyboard lock)")) {
                    Button(L("Open Settings")) { PrivacySettings.openAccessibility() }
                }
                LabeledContent(L("Bluetooth")) {
                    Button(L("Open Settings")) { PrivacySettings.openBluetooth() }
                }
                LabeledContent(L("Full Disk Access (Trash trigger)")) {
                    Button(L("Open Settings")) { PrivacySettings.openFullDiskAccess() }
                }
            } header: {
                Text(L("Permissions"))
            } footer: {
                Text(L("Keyboard & mouse triggers need Input Monitoring. Only key codes are checked — nothing you type is read or stored. Lock keyboard needs Accessibility, because it stops keys instead of just listening. After rebuilding the app you may need to grant it again."))
            }

            Section(L("Advanced")) {
                Button(L("Show sounds folder")) { model.revealSoundsFolder() }
                Button(L("Reset all settings…"), role: .destructive) { confirmReset = true }
            }

            Section(L("About")) {
                LanguagePicker(selection: model.appSettings.language, onSelect: model.setLanguage)
                LabeledContent(L("Version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                Toggle(L("Automatically install updates"), isOn: Binding(
                    get: { model.appSettings.autoUpdateEnabled },
                    set: { model.setAutoUpdate($0) }
                ))
                LabeledContent(L("Software update")) {
                    HStack(spacing: 10) {
                        Text(model.updater.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L("Check for Updates")) { model.checkForUpdates() }
                            .disabled(model.updater.isBusyUpdating)
                    }
                }
                LabeledContent(L("Triggers"), value: "\(TriggerID.allCases.count)")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("Reset all settings?"), isPresented: $confirmReset) {
            Button(L("Reset"), role: .destructive) { model.resetAll() }
        } message: {
            Text(L("Triggers, packs and volumes go back to defaults. Your sound files stay on disk."))
        }
    }

    private func quietBinding(_ keyPath: WritableKeyPath<QuietHours, Bool>) -> Binding<Bool> {
        Binding(get: { model.config.quietHours[keyPath: keyPath] }, set: { value in
            var quiet = model.config.quietHours
            quiet[keyPath: keyPath] = value
            model.update { $0.withQuietHours(quiet) }
        })
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Binding(
            get: { startOfDay.addingTimeInterval(TimeInterval(model.config.quietHours[keyPath: keyPath] * 60)) },
            set: { date in
                var quiet = model.config.quietHours
                quiet[keyPath: keyPath] = PlaybackGate.minuteOfDay(date, calendar: .current)
                model.update { $0.withQuietHours(quiet) }
            }
        )
    }
}
