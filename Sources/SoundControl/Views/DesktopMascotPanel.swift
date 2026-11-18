import AppKit
import Observation
import SoundControlCore
import SwiftUI

/// What one desktop mascot looks like right now. The controller writes it every frame while it walks.
@MainActor
@Observable
final class DesktopMascotSprite {
    private(set) var mascot: Mascot
    private(set) var pose: MascotPose

    init(mascot: Mascot, pose: MascotPose) {
        self.mascot = mascot
        self.pose = pose
    }

    func update(mascot: Mascot, pose: MascotPose) {
        if mascot != self.mascot { self.mascot = mascot }
        if pose != self.pose { self.pose = pose }
    }
}

/// The mascot drawn with the same art as the screen saver, without its drag handling.
private struct DesktopMascotArt: View {
    let sprite: DesktopMascotSprite

    var body: some View {
        let pose = sprite.pose
        let mascot = sprite.mascot
        Canvas { graphics, size in
            MascotArt.draw(mascot, pose: pose, in: &graphics, size: size)
        }
        .frame(width: MascotStroll.size, height: MascotStroll.size)
        .scaleEffect(x: pose.facesRight ? 1 : -1, y: 1)
        .accessibilityHidden(true)
    }
}

/// A transparent, borderless window that floats over everything and lets every click through.
/// It is only as big as the mascot, so it costs almost no memory; the controller moves it as the mascot walks.
final class DesktopMascotPanel: NSPanel {
    @MainActor
    init(sprite: DesktopMascotSprite) {
        let side = MascotStroll.size
        super.init(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: DesktopMascotArt(sprite: sprite))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
