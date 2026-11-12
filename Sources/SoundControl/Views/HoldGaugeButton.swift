import SwiftUI
import SoundControlCore

/// A capsule whose gauge fills over `fillDuration` while `isFilled` and empties quickly when it clears.
/// Changing `fillDuration` while filled retimes the fill that is already running.
struct GaugeCapsule<Leading: View>: View {
    let title: String
    let isFilled: Bool
    let fillDuration: TimeInterval
    @ViewBuilder let leading: () -> Leading

    private struct Phase: Equatable {
        let isFilled: Bool
        let fillDuration: TimeInterval
    }

    private var gaugeAnimation: Animation {
        isFilled ? .linear(duration: fillDuration) : .easeOut(duration: 0.2)
    }

    var body: some View {
        HStack(spacing: 10) {
            leading()
            Text(title).font(.headline)
        }
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
