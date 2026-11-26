import AppKit
import Observation
import SoundControlCore
import SwiftUI

/// What one desktop mascot looks like right now. The controller offers a new picture every frame; it is kept, and
/// the view redrawn, only when it differs, so a resting sprite mascot redraws a few times a second at most.
@MainActor
@Observable
final class DesktopMascotSprite {
    private(set) var drawing: MascotDrawing
    private(set) var side: Double
    private(set) var hue: Double
    @ObservationIgnored private(set) var sheet: MascotSpriteSheet?
    @ObservationIgnored private var mascot: Mascot
    @ObservationIgnored private let cat = MeawkiCatDriver()

    /// A mascot with no colour of its own (the panda) is tinted instead of hue-shifted, which would do nothing.
    var isMonochrome: Bool { mascot == .panda }

    init(mascot: Mascot, pose: MascotPose, size: Double, hue: Double) {
        self.mascot = mascot
        side = size
        self.hue = hue
        let sheet = MascotSpriteSheet.shared(for: mascot)
        self.sheet = sheet
        drawing = .make(mascot: mascot, sheet: sheet, cat: cat, pose: pose, face: .calm, target: nil,
                        size: size)
    }

    func update(mascot: Mascot, pose: MascotPose, face: MascotFace, target: MascotPoint?, size: Double, hue: Double) {
        if size != side { side = size }
        if hue != self.hue { self.hue = hue }
        if mascot != self.mascot {
            self.mascot = mascot
            sheet = MascotSpriteSheet.shared(for: mascot)
        }
        let next = MascotDrawing.make(mascot: mascot, sheet: sheet, cat: cat, pose: pose, face: face, target: target,
                                      size: size)
        if next != drawing { drawing = next }
    }
}

/// The mascot drawn with the same art as the screen saver, without its drag handling.
private struct DesktopMascotArt: View {
    let sprite: DesktopMascotSprite

    var body: some View {
        MascotFigure(drawing: sprite.drawing, sheet: sprite.sheet)
            .modifier(MascotRecolour(hue: sprite.hue, isMonochrome: sprite.isMonochrome))
            .frame(width: sprite.side, height: sprite.side)
    }
}

/// The owner's colour for their mascot: the animal's colours turned around the colour wheel, or, for a black and
/// white animal, a tint over its white.
private struct MascotRecolour: ViewModifier {
    let hue: Double
    let isMonochrome: Bool

    func body(content: Content) -> some View {
        if hue == 0 {
            content
        } else if isMonochrome {
            content.colorMultiply(Color(hue: hue / 360, saturation: 0.45, brightness: 1))
        } else {
            content.hueRotation(.degrees(hue))
        }
    }
}

/// A transparent, borderless window that floats over everything. It is only as big as the mascot, so it costs
/// almost no memory and only the mascot itself takes clicks: click it to poke it, or press, drag and let go to
/// throw it.
/// The controller moves it as the mascot walks or flies.
final class DesktopMascotPanel: NSPanel {
    var onGrab: (NSPoint) -> Void = { _ in }
    var onDrag: (NSPoint) -> Void = { _ in }
    var onRelease: (NSPoint) -> Void = { _ in }
    var onClick: (NSPoint) -> Void = { _ in }

    @MainActor
    init(sprite: DesktopMascotSprite, side: CGFloat) {
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

/// Takes the mouse for the whole mascot, above the drawing, and reports it in screen points. A press only picks the
/// mascot up once the mouse moves a few points; a press and release in place is a click.
private final class MascotGrabView: NSView {
    private static let dragThreshold: CGFloat = 3

    weak var panel: DesktopMascotPanel?
    private var pressedAt: NSPoint?
    private var isDragging = false

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressedAt = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if !isDragging {
            guard let start = pressedAt, hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold else { return }
            isDragging = true
            NSCursor.closedHand.push()
            panel?.onGrab(start)
        }
        panel?.onDrag(point)
    }

    override func mouseUp(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if isDragging {
            NSCursor.pop()
            panel?.onRelease(point)
        } else {
            panel?.onClick(point)
        }
        pressedAt = nil
        isDragging = false
    }
}
