import SwiftUI
import SoundControlCore

/// The Smartheart Screen Saver: title on top, the chosen widgets in the middle, the owner's
/// fingerprint zone at the bottom and the working Claude sessions in the corner the owner picked.
/// The screen dims with `dimmer`; with "bright clock only" the clock holds its own level while the rest goes dark.
struct ScreenSaverView<Unlock: View, Corner: View>: View {
    let settings: ScreenSaverSettings
    let dimmer: ScreenSaverDimmer
    @ViewBuilder let unlock: () -> Unlock
    @ViewBuilder let corner: () -> Corner

    private var screen: Double { dimmer.brightness }

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 0) {
                header.opacity(screen)
                Spacer(minLength: 24)
                widgets
                Spacer(minLength: 24)
                unlock().padding(.bottom, Layout.bottomInset).opacity(screen)
            }
            .padding(.top, Layout.topInset)
            .padding(.horizontal, Layout.sideInset)
            corner()
                .padding(Layout.cornerInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.sessionsCorner.alignment)
                .opacity(screen)
        }
        .foregroundStyle(.white)
        .animation(.linear(duration: 0.5), value: screen)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.accent)
                Text("Smartheart Screen Saver").font(.title2.weight(.semibold))
            }
            Text("Only the owner can unlock.").font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var widgets: some View {
        VStack(spacing: 36) {
            if settings.shows(.clock) {
                ClockWidget().opacity(settings.clockBrightness(screen: screen))
            }
            if settings.shows(.calendar) || settings.shows(.claudeUsage) {
                HStack(alignment: .top, spacing: 28) {
                    if settings.shows(.calendar) { CalendarWidget() }
                    if settings.shows(.claudeUsage) { ClaudeUsageWidget() }
                }
                .opacity(screen)
            }
        }
    }
}

private enum Layout {
    static let topInset: CGFloat = 56
    static let bottomInset: CGFloat = 64
    static let sideInset: CGFloat = 48
    static let cornerInset: CGFloat = 28
}
