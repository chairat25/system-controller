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

/// A transparent, borderless window that floats over everything. It is only as big as the mascot, so it costs
/// almost no memory and only the mascot itself takes clicks: press to pick it up, drag, and let go to throw it.
/// The controller moves it as the mascot walks or flies.
final class DesktopMascotPanel: NSPanel {
    var onGrab: (NSPoint) -> Void = { _ in }
    var onDrag: (NSPoint) -> Void = { _ in }
    var onRelease: (NSPoint) -> Void = { _ in }

    @MainActor
    init(sprite: DesktopMascotSprite) {
        let side = MascotStroll.size
        super.init(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let grab = MascotGrabView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        let host = NSHostingView(rootView: DesktopMascotArt(sprite: sprite))
        host.frame = grab.bounds
        host.autoresizingMask = [.width, .height]
        grab.addSubview(host)
        grab.panel = self
        contentView = grab
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the mouse for the whole mascot, above the drawing, and reports it in screen points.
private final class MascotGrabView: NSView {
    weak var panel: DesktopMascotPanel?

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        panel?.onGrab(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) { panel?.onDrag(NSEvent.mouseLocation) }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        panel?.onRelease(NSEvent.mouseLocation)
    }
}
