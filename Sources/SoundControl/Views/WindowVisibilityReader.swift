import AppKit
import SwiftUI

/// Tells a view whether the window it sits in is on screen. Uses the window's occlusion state, which changes when
/// the window is ordered in or out, and becoming key as a second signal that it is showing.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        VisibilityView(onChange: onChange)
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: @MainActor (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                   queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportCurrent() }
                },
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                   queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report(true) }
                },
            ]
            // Not during the view update that added this view: SwiftUI state may not change then.
            DispatchQueue.main.async { [weak self] in self?.reportCurrent() }
        }

        private func reportCurrent() {
            guard let window else { return }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ isVisible: Bool) {
            guard isVisible != lastReported else { return }
            lastReported = isVisible
            onChange(isVisible)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
