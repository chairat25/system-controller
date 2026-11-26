import SoundControlCore
import SwiftUI

/// What to draw for one mascot. Equatable, so a view only redraws when the picture really changes.
enum MascotDrawing: Equatable {
    /// A rendered animal: a sheet frame with eyes and face drawn on top.
    case sprite(MascotSpriteState)
    /// An animal drawn from shapes, for those without a rendered sheet.
    case shapes(Mascot, MascotPose, MascotFace)
    /// The Meawki cartoon cat, drawn from its animated pose.
    case cartoonCat(MeawkiCat, gaze: MascotPoint, face: MascotFace, facesRight: Bool)

    /// - Parameters:
    ///   - target: the mouse in the mascot's own view points (top-left origin), or nil when unknown.
    ///   - cat: keeps the cartoon cat moving between frames; the cat is drawn from shapes without one.
    @MainActor
    static func make(mascot: Mascot, sheet: MascotSpriteSheet?, cat: MeawkiCatDriver?, pose: MascotPose,
                     face: MascotFace, target: MascotPoint?, size: Double) -> MascotDrawing {
        if mascot == .cat, let cat {
            return cat.drawing(pose: pose, face: face, target: target, size: size)
        }
        guard let sheet else { return .shapes(mascot, pose, face) }
        return .sprite(MascotSpriteState(mascot: mascot, layout: sheet.layout, pose: pose, face: face,
                                         lookingAt: target, viewSize: size))
    }

    var facesRight: Bool {
        switch self {
        case let .sprite(state): state.facesRight
        case let .shapes(_, pose, _): pose.facesRight
        case let .cartoonCat(_, _, _, facesRight): facesRight
        }
    }
}

/// The mascot in a canvas the size of its box, facing either way. Used on the desktop and on the screen saver.
struct MascotFigure: View {
    let drawing: MascotDrawing
    let sheet: MascotSpriteSheet?

    var body: some View {
        Canvas { graphics, size in
            MascotPainter.paint(drawing, sheet: sheet, in: &graphics, size: size)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
enum MascotPainter {
    private static let ink = Color(red: 0.1, green: 0.07, blue: 0.09)

    static func paint(_ drawing: MascotDrawing, sheet: MascotSpriteSheet?, in graphics: inout GraphicsContext,
                      size: CGSize) {
        switch drawing {
        case let .sprite(state):
            guard let sheet else { return }
            paintSprite(state, sheet: sheet, in: &graphics, size: size)
        case let .cartoonCat(cat, gaze, face, facesRight):
            let top = MeawkiCatPainter.draw(cat, gaze: gaze, in: &graphics, size: size)
            drawMark(face, at: top, facesRight: facesRight, size: size.width, in: &graphics)
        case let .shapes(mascot, pose, face):
            var flipped = graphics
            if !pose.facesRight {
                flipped.translateBy(x: size.width, y: 0)
                flipped.scaleBy(x: -1, y: 1)
            }
            MascotArt.draw(mascot, pose: pose, in: &flipped, size: size)
            // The shapes are drawn in a 72-point box with the head top near (42, 10).
            let x = (pose.facesRight ? 42 : 30) / 72 * size.width
            drawMark(face, at: CGPoint(x: x, y: 10 / 72 * size.height), facesRight: pose.facesRight,
                     size: size.width, in: &graphics)
        }
    }

    // MARK: - Sprite

    private static func paintSprite(_ state: MascotSpriteState, sheet: MascotSpriteSheet,
                                    in graphics: inout GraphicsContext, size: CGSize) {
        let layout = sheet.layout
        let pixels = Double(MascotSpriteLayout.framePixels)
        let scale = size.width / pixels
        if state.isOnFloor {
            let footX = state.facesRight ? layout.floorX : pixels - layout.floorX
            let shadow = CGRect(x: footX * scale - size.width * 0.24,
                                y: MascotSpriteLayout.floorY * scale - size.height * 0.035,
                                width: size.width * 0.48, height: size.height * 0.07)
            graphics.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.22)))
        }
        guard let frame = sheet.frame(state.frame) else { return }
        let image = Image(decorative: frame, scale: 1, orientation: state.facesRight ? .up : .upMirrored)
        graphics.draw(image, in: CGRect(origin: .zero, size: size))

        let spots = layout.frames[state.frame]
        let lid = Color(red: layout.lidColor.red, green: layout.lidColor.green, blue: layout.lidColor.blue)
        for (spot, isNear) in [(spots.far, false), (spots.near, true)] where spot.isVisible {
            let center = MascotSpriteState.eyeCenter(spot, facesRight: state.facesRight, viewSize: size.width)
            let eye = Eye(center: CGPoint(x: center.x, y: center.y), radius: spot.radius * scale,
                          front: state.facesRight ? 1 : -1)
            drawEye(eye, state: state, pupil: layout.pupil, lid: lid, in: &graphics)
            if isNear { drawBrow(eye, face: state.face, in: &graphics) }
        }
        let top = MascotSpriteState.viewPoint(spots.headTop, facesRight: state.facesRight, viewSize: size.width)
        drawMark(state.face, at: CGPoint(x: top.x, y: top.y), facesRight: state.facesRight, size: size.width,
                 in: &graphics)
    }

    private struct Eye {
        let center: CGPoint
        let radius: CGFloat
        /// +1 when the face points right, -1 when left.
        let front: CGFloat

        func rect(_ factor: CGFloat) -> CGRect {
            CGRect(x: center.x - radius * factor, y: center.y - radius * factor,
                   width: radius * factor * 2, height: radius * factor * 2)
        }
    }

    private static func drawEye(_ eye: Eye, state: MascotSpriteState, pupil shape: MascotPupilShape, lid: Color,
                                in graphics: inout GraphicsContext) {
        var inside = graphics
        inside.clip(to: Path(ellipseIn: eye.rect(0.96)))
        let r = eye.radius
        let center = CGPoint(x: eye.center.x + state.gaze.x * r, y: eye.center.y + state.gaze.y * r)
        let dilation = pupilDilation(state.face)
        let pupil: CGRect
        switch shape {
        case .round:
            let size = r * 0.58 * dilation
            pupil = CGRect(x: center.x - size, y: center.y - size, width: size * 2, height: size * 2)
        case .slit:
            let isOpen = state.face == .curious || state.face == .veryCurious
            let width = r * (isOpen ? 0.62 : 0.3) * dilation
            let height = r * 1.3
            pupil = CGRect(x: center.x - width, y: center.y - height / 2 - r * 0.05, width: width * 2, height: height)
        }
        inside.fill(Path(ellipseIn: pupil), with: .color(ink))
        let shine = r * 0.24
        inside.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.3 - shine, y: center.y - r * 0.32 - shine,
                                           width: shine * 2, height: shine * 2)), with: .color(.white.opacity(0.95)))
        drawLid(eye, state: state, color: lid, in: &inside)
    }

    private static func pupilDilation(_ face: MascotFace) -> CGFloat {
        switch face {
        case .calm: 1
        case .curious: 1.15
        case .veryCurious: 1.3
        case .annoyed: 0.85
        case .fleeing: 0.7
        case .sleepy: 1
        case .happy: 1.1
        case .love: 1.25
        }
    }

    /// Closed for a blink; half shut and slanted toward the nose when annoyed.
    private static func drawLid(_ eye: Eye, state: MascotSpriteState, color: Color, in graphics: inout GraphicsContext) {
        let r = eye.radius
        let line = StrokeStyle(lineWidth: max(r * 0.28, 0.8), lineCap: .round)
        if state.isBlinking {
            graphics.fill(Path(eye.rect(1.1)), with: .color(color))
            var shut = Path()
            shut.move(to: CGPoint(x: eye.center.x - r, y: eye.center.y))
            shut.addQuadCurve(to: CGPoint(x: eye.center.x + r, y: eye.center.y),
                              control: CGPoint(x: eye.center.x, y: eye.center.y + r * 0.5))
            graphics.stroke(shut, with: .color(ink.opacity(0.8)), style: line)
            return
        }
        guard state.face == .annoyed else { return }
        let back = CGPoint(x: eye.center.x - eye.front * r * 1.1, y: eye.center.y - r * 0.55)
        let nose = CGPoint(x: eye.center.x + eye.front * r * 1.1, y: eye.center.y - r * 0.02)
        var cover = Path()
        cover.move(to: back)
        cover.addLine(to: nose)
        cover.addLine(to: CGPoint(x: nose.x, y: eye.center.y - r * 1.2))
        cover.addLine(to: CGPoint(x: back.x, y: eye.center.y - r * 1.2))
        cover.closeSubpath()
        graphics.fill(cover, with: .color(color))
        var edge = Path()
        edge.move(to: back)
        edge.addLine(to: nose)
        graphics.stroke(edge, with: .color(ink.opacity(0.85)), style: line)
    }

    private static func drawBrow(_ eye: Eye, face: MascotFace, in graphics: inout GraphicsContext) {
        let r = eye.radius
        let c = eye.center
        let f = eye.front
        var brow = Path()
        switch face {
        case .calm, .sleepy, .happy, .love:
            return
        case .curious, .veryCurious:
            let lift: CGFloat = face == .curious ? 1.9 : 2.3
            brow.move(to: CGPoint(x: c.x - f * r * 0.9, y: c.y - r * (lift - 0.3)))
            brow.addQuadCurve(to: CGPoint(x: c.x + f * r * 0.9, y: c.y - r * (lift - 0.4)),
                              control: CGPoint(x: c.x, y: c.y - r * (lift + 0.5)))
        case .annoyed:
            brow.move(to: CGPoint(x: c.x - f * r * 1.0, y: c.y - r * 1.85))
            brow.addLine(to: CGPoint(x: c.x + f * r * 1.0, y: c.y - r * 1.15))
        case .fleeing:
            brow.move(to: CGPoint(x: c.x - f * r * 1.0, y: c.y - r * 1.3))
            brow.addLine(to: CGPoint(x: c.x + f * r * 1.0, y: c.y - r * 1.9))
        }
        graphics.stroke(brow, with: .color(ink.opacity(0.8)),
                        style: StrokeStyle(lineWidth: max(r * 0.38, 1), lineCap: .round))
    }

    // MARK: - Mood marks

    /// A sign over the head: one question mark, then two, an anger mark, and sweat while it runs.
    private static func drawMark(_ face: MascotFace, at top: CGPoint, facesRight: Bool, size: CGFloat,
                                 in graphics: inout GraphicsContext) {
        let front: CGFloat = facesRight ? 1 : -1
        let font = Font.system(size: size * 0.17)
        switch face {
        case .calm:
            return
        case .curious:
            graphics.draw(Text(L("❓")).font(font), at: CGPoint(x: top.x + front * size * 0.06, y: top.y - size * 0.05))
        case .veryCurious:
            graphics.draw(Text(L("❓")).font(font), at: CGPoint(x: top.x - front * size * 0.02, y: top.y - size * 0.03))
            graphics.draw(Text(L("❓")).font(.system(size: size * 0.21)),
                          at: CGPoint(x: top.x + front * size * 0.12, y: top.y - size * 0.09))
        case .annoyed:
            graphics.draw(Text(L("💢")).font(font), at: CGPoint(x: top.x + front * size * 0.1, y: top.y - size * 0.02))
        case .fleeing:
            graphics.draw(Text(L("💦")).font(font), at: CGPoint(x: top.x - front * size * 0.12, y: top.y + size * 0.02))
        case .sleepy:
            graphics.draw(Text(L("💤")).font(font), at: CGPoint(x: top.x + front * size * 0.1, y: top.y - size * 0.04))
        case .happy:
            graphics.draw(Text(L("🎵")).font(font), at: CGPoint(x: top.x + front * size * 0.1, y: top.y - size * 0.04))
        case .love:
            graphics.draw(Text(L("💕")).font(font), at: CGPoint(x: top.x + front * size * 0.06, y: top.y - size * 0.05))
        }
    }
}
