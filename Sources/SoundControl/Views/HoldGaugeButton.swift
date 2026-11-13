import SwiftUI
import SoundControlCore

/// A capsule whose gauge fills over `fillDuration` while `isFilled` and drains slowly when it clears.
/// Changing `fillDuration` while filled retimes the fill that is already running.
struct GaugeCapsule<Leading: View>: View {
    let title: String
    let isFilled: Bool
    let fillDuration: TimeInterval
    /// False keeps the capsule at the title's size but shows only the box and its gauge.
    var showsTitle = true
    @ViewBuilder let leading: () -> Leading

    /// Letting go drains the gauge slowly, so a short touch still reads as progress.
    private static var emptyDuration: TimeInterval { 0.8 }

    private struct Phase: Equatable {
        let isFilled: Bool
        let fillDuration: TimeInterval
    }

    private var gaugeAnimation: Animation {
        isFilled ? .linear(duration: fillDuration) : .smooth(duration: Self.emptyDuration)
    }

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Text(title).font(.headline).opacity(showsTitle ? 1 : 0)
        }
        .accessibilityLabel(title)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Theme.accent)
                        .frame(width: proxy.size.width * (isFilled ? 1 : 0))
                        .animation(gaugeAnimation, value: Phase(isFilled: isFilled, fillDuration: fillDuration))
                }
            }
        }
        .clipShape(Capsule())
    }
}

/// Cleaning lock: unlocks once the gauge is full, so a palm brushing the trackpad does not unlock.
struct TimedHoldButton: View {
    let onUnlock: @MainActor () -> Void
    @State private var isHolding = false

    var body: some View {
        GaugeCapsule(title: "Hold to unlock", isFilled: isHolding, fillDuration: KeyboardLock.holdToUnlock) {
            EmptyView()
        }
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: KeyboardLock.holdToUnlock, maximumDistance: 40) {
            onUnlock()
        } onPressingChanged: { isPressing in
            isHolding = isPressing
        }
    }
}
