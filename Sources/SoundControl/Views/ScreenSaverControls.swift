import SwiftUI
import SoundControlCore

/// Applies a change to the screen saver settings and saves it.
typealias ScreenSaverUpdate = @MainActor ((ScreenSaverSettings) -> ScreenSaverSettings) -> Void

/// The screen saver settings and a way to change them, handed to views that live outside the popup
/// (the screen saver itself). Reading `settings` inside a view body keeps the view in step with every change.
struct ScreenSaverLink {
    let read: @MainActor () -> ScreenSaverSettings
    let update: ScreenSaverUpdate

    @MainActor var settings: ScreenSaverSettings { read() }

    /// Fixed settings that ignore changes, for the cleaning lock.
    static func fixed(_ settings: ScreenSaverSettings) -> Self {
        Self(read: { settings }, update: { _ in })
    }
}

// The controls below use no menus: on the screen saver a pop-up menu would open underneath the overlay.

/// When the screen dims, how long the fade takes and how dark it gets.
struct DimmingControls: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate

    private static let dimAfterChoices = [10, 30, 60, 120, 300, 600, 1800, 3600]
    private static let fadeChoices = [0, 1, 3, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("Dim the screen when left alone"), isOn: Binding(
                get: { settings.isDimEnabled },
                set: { value in update { $0.withDimEnabled(value) } }))
            Group {
                presetStepper("Start dimming after", value: settings.dimAfterSeconds, presets: Self.dimAfterChoices,
                              label: Self.duration) { value in update { $0.withDimAfter(seconds: value) } }
                presetStepper("Fade out over", value: settings.fadeSeconds, presets: Self.fadeChoices,
                              label: { $0 == 0 ? "Instantly" : Self.duration($0) }) { value in update { $0.withFade(seconds: value) } }
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(L("Darkest level"), value: Self.levelLabel(settings.dimLevel))
                    Slider(value: Binding(get: { settings.dimLevel },
                                          set: { value in update { $0.withDimLevel(value) } }), in: 0...1)
                }
            }
            .disabled(!settings.isDimEnabled)
        }
    }

    private func presetStepper(_ title: String, value: Int, presets: [Int], label: @escaping (Int) -> String,
                               onChange: @escaping (Int) -> Void) -> some View {
        Stepper {
            LabeledContent(title, value: label(value))
        } onIncrement: {
            onChange(Presets.step(presets, from: value, by: 1))
        } onDecrement: {
            onChange(Presets.step(presets, from: value, by: -1))
        }
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) hr"
    }

    private static func levelLabel(_ level: Double) -> String {
        level == 0 ? L("Fully dark") : "\(Int((level * 100).rounded()))%"
    }
}

/// What keeps its own brightness while the rest of the screen dims.
struct StayLitControls: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate

    private static let litRange: ClosedRange<Double> = 0.05...1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            litControl("Clock", isOn: settings.isClockBright, level: settings.clockLevel,
                       setOn: { value in update { $0.withClockBright(value) } },
                       setLevel: { value in update { $0.withClockLevel(value) } })
            if settings.activeMascot != .none {
                litControl(settings.activeMascot.title, isOn: settings.isMascotBright, level: settings.mascotLevel,
                           setOn: { value in update { $0.withMascotBright(value) } },
                           setLevel: { value in update { $0.withMascotLevel(value) } })
            }
            Text(L("Ticked items keep this brightness while the rest of the screen dims."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func litControl(_ title: String, isOn: Bool, level: Double,
                            setOn: @escaping (Bool) -> Void, setLevel: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { isOn }, set: setOn)) {
                LabeledContent(title, value: "\(Int((level * 100).rounded()))%")
            }
            Slider(value: Binding(get: { level }, set: setLevel), in: Self.litRange)
                .disabled(!isOn)
        }
    }
}

/// Which widgets the screen saver shows. Every widget is one switch row with its icon.
struct WidgetToggles: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.control) {
            widgetToggle(L("Clock"), systemImage: "clock", widget: .clock)
            widgetToggle(L("Calendar"), systemImage: "calendar", widget: .calendar)
            widgetToggle(L("Claude usage"), systemImage: "sparkle", widget: .claudeUsage)
            SettingToggle(title: "Claude sessions", systemImage: "terminal", isOn: settings.showsSessions,
                          onChange: { value in update { $0.withShowsSessions(value) } })
        }
    }

    private func widgetToggle(_ title: String, systemImage: String, widget: ScreenSaverWidget) -> some View {
        SettingToggle(title: title, systemImage: systemImage, isOn: settings.shows(widget),
                      onChange: { value in update { $0.showing(widget, value) } })
    }
}

/// Where the Claude sessions list sits on the screen saver.
struct SessionsCornerRow: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate

    var body: some View {
        SettingRow("Sessions position", detail: settings.sessionsCorner.title, systemImage: "rectangle.inset.topright.filled") {
            CornerPicker(selection: settings.sessionsCorner,
                         onSelect: { corner in update { $0.withSessionsCorner(corner) } })
        }
        .disabled(!settings.showsSessions)
        .opacity(settings.showsSessions ? 1 : 0.5)
    }
}

/// Resets custom dragged widget positions and stacking order back to the balanced default layout.
struct WidgetLayoutResetButton: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate

    var body: some View {
        if settings.hasCustomWidgetLayout {
            Button {
                update { $0.resetWidgetLayout() }
            } label: {
                Label(L("Reset widget positions"), systemImage: "arrow.counterclockwise")
            }
        }
    }
}

/// Hide toggle and animal picker for the screen saver mascot, preserving the chosen animal when hidden.
struct MascotControls: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate
    /// Kept on this Mac only, not in the synced screen saver settings.
    let appSettings: AppSettings
    let updateApp: (@escaping (AppSettings) -> AppSettings) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.control) {
            SettingToggle(
                title: "Hide mascot",
                detail: settings.activeMascot == .none
                    ? "Hidden on the screen saver"
                    : "Roams the main display — drag to place it anywhere",
                systemImage: "pawprint",
                isOn: settings.activeMascot == .none,
                onChange: { isHidden in update { $0.withMascotHidden(isHidden) } }
            )
            MascotGrid(selection: settings.activeMascot) { mascot in
                update { $0.withMascot(mascot) }
            }
            .opacity(settings.activeMascot == .none ? 0.55 : 1)
            VStack(alignment: .leading, spacing: Spacing.control) {
                MascotStyleControls(style: appSettings.mascotStyle) { style in
                    updateApp { $0.withMascotStyle(style) }
                }
                ThrowFrameRatePicker(selection: appSettings.throwFrameRate) { rate in
                    updateApp { $0.withThrowFrameRate(rate) }
                }
            }
            .disabled(settings.activeMascot == .none)
            .opacity(settings.activeMascot == .none ? 0.55 : 1)
        }
    }
}

/// Size, number and colour of this Mac's desktop mascots. Each change shows on the desktop at once.
struct MascotStyleControls: View {
    let style: MascotStyle
    let onChange: (MascotStyle) -> Void

    private func with(scale: Double? = nil, count: Int? = nil, hue: Double? = nil) -> MascotStyle {
        MascotStyle(scale: scale ?? style.scale, count: count ?? style.count, hue: hue ?? style.hue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.control) {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                SettingRow("Mascot size", detail: "This Mac only", systemImage: "arrow.up.left.and.arrow.down.right") {
                    Text(String(format: "%.2f×", style.scale)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { style.scale }, set: { onChange(with(scale: $0)) }),
                       in: MascotStyle.scaleRange, step: 0.05)
                    .labelsHidden()
                    .accessibilityLabel(L("Mascot size"))
            }
            SettingRow("How many", detail: "More of the same animal on the desktop", systemImage: "square.on.square") {
                HStack(spacing: Spacing.related) {
                    Text("\(style.count)").font(.callout.monospacedDigit())
                    Stepper(L("How many"), value: Binding(get: { style.count }, set: { onChange(with(count: $0)) }),
                            in: MascotStyle.countRange)
                        .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: Spacing.micro) {
                SettingRow("Color", detail: "Turn the colors of the animal around", systemImage: "paintpalette") {
                    Button(L("Original")) { onChange(with(hue: 0)) }
                        .controlSize(.small)
                        .disabled(!style.isRecoloured)
                }
                HueSlider(hue: style.hue) { onChange(with(hue: $0)) }
            }
        }
    }
}

/// A slider whose track is the colour wheel, so the colour you want sits where you put the thumb.
struct HueSlider: View {
    let hue: Double
    let onChange: (Double) -> Void

    private static let trackHeight: CGFloat = 10
    private static let thumb: CGFloat = 18

    private static let wheel = Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        Color(hue: $0, saturation: 0.85, brightness: 0.95)
    })

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - Self.thumb, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(gradient: Self.wheel, startPoint: .leading, endPoint: .trailing))
                    .frame(height: Self.trackHeight)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                Circle()
                    .fill(Color(hue: hue / 360, saturation: hue == 0 ? 0 : 0.85, brightness: 0.95))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .frame(width: Self.thumb, height: Self.thumb)
                    .offset(x: travel * hue / 360)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let fraction = min(max((value.location.x - Self.thumb / 2) / travel, 0), 1)
                onChange(fraction * 359)
            })
        }
        .frame(height: Self.thumb + 4)
        .accessibilityElement()
        .accessibilityLabel(L("Color"))
        .accessibilityValue("\(Int(hue))°")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(hue + 15, 359))
            case .decrement: onChange(max(hue - 15, 0))
            @unknown default: break
            }
        }
    }
}

/// Frame rate of a held or thrown mascot, as a dropdown. Applies to this Mac only.
struct ThrowFrameRatePicker: View {
    let selection: ThrowFrameRate
    let onSelect: (ThrowFrameRate) -> Void

    var body: some View {
        SettingRow("Throw frame rate", detail: "This Mac only", systemImage: "speedometer") {
            Picker(L("Throw frame rate"), selection: Binding(get: { selection }, set: onSelect)) {
                ForEach(ThrowFrameRate.allCases) { rate in
                    Text(L(rate.title)).tag(rate)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 140)
        }
    }
}

/// The animals as buttons, three to a row.
struct MascotGrid: View {
    let selection: Mascot
    let onSelect: (Mascot) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(Mascot.allCases) { mascot in
                let isSelected = mascot == selection
                Button { onSelect(mascot) } label: {
                    Text(L(mascot.title))
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .glassChip(isSelected: isSelected)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Backdrop picker for the screen saver: dark themes, macOS wallpaper, and optional custom photo.
struct BackgroundControls: View {
    let settings: ScreenSaverSettings
    let update: ScreenSaverUpdate
    var onChoosePhoto: (() -> Void)? = nil
    var onClearPhoto: (() -> Void)? = nil

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var choices: [ScreenSaverBackground] {
        if settings.customBackgroundName != nil {
            return ScreenSaverBackground.presets + [.customImage]
        }
        return ScreenSaverBackground.presets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.control) {
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(choices) { background in
                    let isSelected = background == settings.background
                    Button {
                        update { $0.withBackground(background) }
                    } label: {
                        HStack(spacing: 5) {
                            swatch(for: background)
                            Text(L(background.title))
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                        .glassChip(isSelected: isSelected)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            if let onChoosePhoto {
                HStack(spacing: Spacing.related) {
                    Image(systemName: "photo")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.rowIconWidth)
                    Text(settings.customBackgroundName ?? "Custom photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.related)
                    if settings.customBackgroundName != nil, let onClearPhoto {
                        Button(L("Remove"), role: .destructive, action: onClearPhoto)
                            .controlSize(.small)
                    }
                    Button(L(settings.customBackgroundName == nil ? "Choose photo…" : "Change…"), action: onChoosePhoto)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func swatch(for background: ScreenSaverBackground) -> some View {
        switch background {
        case .pitchBlack:
            Circle().fill(Color.black)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75))
                .frame(width: 11, height: 11)
        case .midnight:
            swatchCircle([Color(red: 0.08, green: 0.12, blue: 0.38), Color(red: 0.14, green: 0.08, blue: 0.35)])
        case .aurora:
            swatchCircle([Color(red: 0.05, green: 0.45, blue: 0.48), Color(red: 0.25, green: 0.16, blue: 0.45)])
        case .ember:
            swatchCircle([Color(red: 0.55, green: 0.18, blue: 0.08), Color(red: 0.28, green: 0.06, blue: 0.10)])
        case .ocean:
            swatchCircle([Color(red: 0.06, green: 0.30, blue: 0.58), Color(red: 0.04, green: 0.15, blue: 0.35)])
        case .forest:
            swatchCircle([Color(red: 0.08, green: 0.36, blue: 0.22), Color(red: 0.03, green: 0.16, blue: 0.10)])
        case .cosmos:
            swatchCircle([Color(red: 0.14, green: 0.10, blue: 0.36), Color(red: 0.04, green: 0.04, blue: 0.14)])
        case .desktopWallpaper:
            Image(systemName: "macwindow").font(.system(size: 10, weight: .semibold))
        case .customImage:
            Image(systemName: "photo.fill").font(.system(size: 10, weight: .semibold))
        }
    }

    private func swatchCircle(_ colors: [Color]) -> some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            .frame(width: 11, height: 11)
    }
}
