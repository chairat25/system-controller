import SoundControlCore
import SwiftUI

/// Keeps one cartoon cat's animation between frames and turns a mascot pose into its next picture.
/// Not observed: the drawing it returns is what views watch.
@MainActor
final class MeawkiCatDriver {
    private var cat = MeawkiCat.start
    private var last: Date?

    func drawing(pose: MascotPose, face: MascotFace, target: MascotPoint?, size: Double, now: Date = Date())
        -> MascotDrawing {
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        let eye = MeawkiCatPainter.eyePoint(facesRight: pose.facesRight, size: size)
        let gaze = MascotSpriteState.gaze(from: eye, to: target, facesRight: pose.facesRight)
        let mode = MeawkiCat.mode(for: pose, face: face)
        let speed = MascotRoute.speed * (mode == .run ? 3.2 : 1)
        let tilt = face == .veryCurious ? 0.35 : face == .curious ? 0.18 : 0
        cat = cat.advanced(by: dt, mode: mode, facesRight: pose.facesRight, look: -gaze.y * 0.8, tilt: tilt,
                           speed: speed)
        return .cartoonCat(cat, gaze: gaze, face: face, facesRight: pose.facesRight)
    }
}

/// Draws the Meawki cartoon cat (github.com/phanumat44/Meawki, ISC licence), ported from renderer/cat2d.js:
/// an orange tabby in model units with y up, feet at the origin, scaled into the mascot's box.
@MainActor
enum MeawkiCatPainter {
    private static let ink = rgb(0x3B2A20)
    private static let baseHex = 0xF5A35A
    private static let base = rgb(baseHex)
    private static let dark = rgb(0xD9782F)
    private static let belly = rgb(0xFFF3E2)
    private static let iris = rgb(0x6B8F2A)
    private static let pink = rgb(0xF4A3AD)
    /// Model units to view points, as a share of the box: the whole cat, tail to whiskers, fits with room above.
    private static let unitsAcross: CGFloat = 140
    /// Feet sit a little above the box bottom, so a sitting cat's tail stays inside.
    private static let floorShare: CGFloat = 0.86

    /// Roughly where the cat's eyes are in its box, for pointing the pupils at the mouse.
    static func eyePoint(facesRight: Bool, size: Double) -> MascotPoint {
        let x = size * (facesRight ? 0.78 : 0.22)
        return MascotPoint(x: x, y: size * 0.42)
    }

    /// Draws the cat and returns the spot just above its head, in view points.
    static func draw(_ cat: MeawkiCat, gaze: MascotPoint, in graphics: inout GraphicsContext, size: CGSize)
        -> CGPoint {
        var top = CGPoint(x: size.width / 2, y: size.height * 0.2)
        var outer = graphics
        // A faint halo around the whole silhouette, applied once, so the cat shows on white windows.
        outer.addFilter(.shadow(color: Color(red: 0.18, green: 0.14, blue: 0.12).opacity(0.38), radius: 1.5, y: 1))
        outer.drawLayer { layer in
            top = drawCat(cat, gaze: gaze, in: &layer, size: size)
        }
        return top
    }

    private static func drawCat(_ cat: MeawkiCat, gaze: MascotPoint, in graphics: inout GraphicsContext,
                                size: CGSize) -> CGPoint {
        let p = cat.pose
        let scale = size.width / unitsAcross
        var g = graphics
        g.translateBy(x: size.width / 2 + 7 * scale * cat.facing, y: size.height * floorShare)
        g.scaleBy(x: scale * cat.facing, y: -scale)
        g.translateBy(x: -4, y: p.y)
        g.scaleBy(x: p.sx, y: p.sy)

        var contact = g
        contact.scaleBy(x: 1, y: 0.18)
        contact.fill(ellipse(6, 0, 42, 14), with: .color(.black.opacity(0.13)))

        var body = g
        body.translateBy(x: -16, y: 26)
        body.rotate(by: .radians(p.pitch))
        tail(cat, in: &body)
        leg(at: (4, -2), hip: p.blh - p.pitch, knee: p.blk, upper: 1, isFar: true, in: &body)
        leg(at: (36, -2), hip: p.flh - p.pitch, knee: p.flk, upper: p.frontScale, isFar: true, in: &body)
        torso(in: &body)
        let fold = min(1, max(0, -p.brk / 2.2))
        if fold > 0.15 {
            body.fill(ellipse(6, 1, 9 + fold * 6, 7 + fold * 6, rotation: 0.3), with: .color(shade(baseHex, -0.05)))
        }
        leg(at: (6, -2), hip: p.brh - p.pitch, knee: p.brk, upper: 1, isFar: false, in: &body)
        let isPawUp = p.tongue > 0.3
        if !isPawUp {
            leg(at: (38, -2), hip: p.frh - p.pitch, knee: p.frk, upper: p.frontScale, isFar: false, in: &body)
        }

        var head = body
        head.translateBy(x: 44, y: 14)
        head.rotate(by: .radians(-p.neck - p.pitch * 0.7))
        head.translateBy(x: 4, y: 6)
        head.rotate(by: .radians(-p.headTilt * 0.6))
        head.scaleBy(x: 1.2, y: 1.2)
        drawHead(cat, gaze: gaze, in: &head)
        if isPawUp {
            // A soft shadow keeps the licked paw from melting into the chest.
            var paw = body
            paw.addFilter(.shadow(color: Color(red: 0.24, green: 0.14, blue: 0.08).opacity(0.35), radius: 1.2))
            leg(at: (38, -2), hip: p.frh - p.pitch, knee: p.frk, upper: p.frontScale, isFar: false, in: &paw)
        }
        return CGPoint(x: 3, y: 20).applying(head.transform)
    }

    // MARK: - Parts

    private static func leg(at hip: (CGFloat, CGFloat), hip angle: Double, knee: Double, upper: Double,
                            isFar: Bool, in g: inout GraphicsContext) {
        let l1 = 12 * upper, l2 = 12.0
        let kx = hip.0 + sin(angle) * l1, ky = hip.1 - cos(angle) * l1
        let fx = kx + sin(angle + knee) * l2, fy = ky - cos(angle + knee) * l2
        let fur = isFar ? shade(baseHex, -0.14) : base
        capsule([CGPoint(x: hip.0, y: hip.1), CGPoint(x: kx, y: ky), CGPoint(x: fx, y: fy)], width: 9, color: fur,
                in: &g)
        g.fill(ellipse(fx + 1.6, fy + 1.2, 5.4, 3.6), with: .color(fur))
    }

    private static func torso(in g: inout GraphicsContext) {
        let shape = ellipse(19, 5, 30, 16, rotation: 0.04)
        g.fill(shape, with: .color(base))
        var inside = g
        inside.clip(to: shape)
        inside.fill(ellipse(30, -8, 22, 11, rotation: -0.15), with: .color(belly))
        var stripes = Path()
        for sx in [-4.0, 6, 16, 26] {
            stripes.move(to: CGPoint(x: sx, y: 23))
            stripes.addQuadCurve(to: CGPoint(x: sx + 1, y: 7), control: CGPoint(x: sx + 5, y: 14))
        }
        inside.stroke(stripes, with: .color(dark), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
    }

    private static func tail(_ cat: MeawkiCat, in g: inout GraphicsContext) {
        let p = cat.pose
        var points = [CGPoint(x: -12, y: 8)]
        var angle = 0.0
        for i in 0..<9 {
            let wave = sin(cat.time * p.tailSpeed - Double(i) * 0.55) * p.tailWave * (0.4 + Double(i) / 9)
            angle += (i == 0 ? -p.tailLift : 0) - p.tailCurl * (i > 0 ? 1 : 0) + wave * 0.9
            let last = points[points.count - 1]
            points.append(CGPoint(x: last.x - cos(angle) * 4.6, y: last.y - sin(angle) * 4.6))
        }
        let width = 7 + p.puff * 7
        capsule(points, width: width, color: base, in: &g)
        var rings = Path()
        rings.move(to: points[7])
        rings.addLine(to: points[9])
        for i in [3, 5] {
            rings.move(to: points[i])
            rings.addLine(to: lerp(points[i], points[i + 1], 0.45))
        }
        g.stroke(rings, with: .color(dark), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private static func drawHead(_ cat: MeawkiCat, gaze: MascotPoint, in g: inout GraphicsContext) {
        let p = cat.pose
        let eyeOpen = cat.blink > 0 ? 0 : p.eye
        for (ex, ey, rot, isFar) in [(11.0, 10.0, -0.15, true), (-3.0, 11.0, 0.25, false)] {
            var ear = g
            ear.translateBy(x: ex, y: ey)
            ear.rotate(by: .radians(rot - p.ear * 0.6))
            var shape = Path()
            shape.move(to: CGPoint(x: -6.5, y: -1))
            shape.addQuadCurve(to: CGPoint(x: 0.5, y: 13), control: CGPoint(x: -3, y: 9))
            shape.addQuadCurve(to: CGPoint(x: 6.5, y: -1), control: CGPoint(x: 4, y: 8))
            shape.closeSubpath()
            ear.fill(shape, with: .color(isFar ? shade(baseHex, -0.12) : base))
            if !isFar {
                var inner = Path()
                inner.move(to: CGPoint(x: -3.5, y: 0.5))
                inner.addQuadCurve(to: CGPoint(x: 0.4, y: 8.5), control: CGPoint(x: -1, y: 6))
                inner.addQuadCurve(to: CGPoint(x: 3.6, y: 0.5), control: CGPoint(x: 2.2, y: 5))
                ear.fill(inner, with: .color(pink))
            }
        }
        let skull = ellipse(3, 1, 16.5, 14)
        g.fill(skull, with: .color(base))
        var marked = g
        marked.clip(to: skull)
        var stripes = Path()
        for sx in [-1.0, 4, 9] {
            stripes.move(to: CGPoint(x: sx, y: 15))
            stripes.addLine(to: CGPoint(x: sx + 0.8, y: 9))
        }
        stripes.move(to: CGPoint(x: -13, y: 3)); stripes.addLine(to: CGPoint(x: -8, y: 3.5))
        stripes.move(to: CGPoint(x: -13, y: -1)); stripes.addLine(to: CGPoint(x: -8, y: 0))
        marked.stroke(stripes, with: .color(dark), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        let yaw = p.headYaw * 3
        g.fill(ellipse(12 + yaw, -5, 6.5, 4.6), with: .color(belly))
        g.fill(ellipse(1 + yaw, -4, 3.6, 2.2), with: .color(Color(red: 1, green: 0.47, blue: 0.55).opacity(0.35)))
        // Screen gaze to model units: the drawing is mirrored when facing left and its y points up.
        let look = CGPoint(x: gaze.x / 0.45 * (cat.facing < 0 ? -1 : 1), y: -gaze.y / 0.45)
        for (ex, r) in [(4 + yaw, 1.0), (14.5 + yaw, 0.85)] {
            eye(x: ex, y: 2.5, r: r, open: eyeOpen, look: look, in: &g)
        }
        face(p, yaw: yaw, in: &g)
    }

    private static func face(_ p: MeawkiCatPose, yaw: Double, in g: inout GraphicsContext) {
        var nose = Path()
        nose.move(to: CGPoint(x: 12 + yaw, y: -2.2))
        nose.addLine(to: CGPoint(x: 15 + yaw, y: -2.2))
        nose.addLine(to: CGPoint(x: 13.5 + yaw, y: -4))
        nose.closeSubpath()
        g.fill(nose, with: .color(rgb(0xEE7E93)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 13.5 + yaw, y: -4))
        mouth.addQuadCurve(to: CGPoint(x: 11 + yaw, y: -5.6), control: CGPoint(x: 12.8 + yaw, y: -6.4))
        mouth.move(to: CGPoint(x: 13.5 + yaw, y: -4))
        mouth.addQuadCurve(to: CGPoint(x: 16 + yaw, y: -5.6), control: CGPoint(x: 14.4 + yaw, y: -6.4))
        g.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        if p.mouth > 0.15 { // hiss
            let h = 5.5 * p.mouth
            g.fill(ellipse(13.5 + yaw, -5.2 - h * 0.5, 3.4, h * 0.6 + 0.4), with: .color(rgb(0x7A2D38)))
            g.fill(ellipse(13.5 + yaw, -5.4 - h * 0.85, 2.2, h * 0.25 + 0.2), with: .color(rgb(0xF08A9A)))
            var fangs = Path()
            for fx in [11.4, 15.6] {
                fangs.move(to: CGPoint(x: fx - 0.7 + yaw, y: -5))
                fangs.addLine(to: CGPoint(x: fx + 0.7 + yaw, y: -5))
                fangs.addLine(to: CGPoint(x: fx + yaw, y: -6.6))
                fangs.closeSubpath()
            }
            g.fill(fangs, with: .color(.white))
        }
        if p.tongue > 0.3 { // grooming lick
            g.fill(ellipse(15.5 + yaw, -7.2, 2 * p.tongue, 1.4 * p.tongue, rotation: 0.4), with: .color(rgb(0xF07F92)))
        }
        var whiskers = Path()
        for dy in [-3.0, -5.5] {
            whiskers.move(to: CGPoint(x: 17 + yaw, y: dy))
            whiskers.addLine(to: CGPoint(x: 26 + yaw, y: dy + (dy + 4) * 0.6))
        }
        g.stroke(whiskers, with: .color(Color(red: 0.23, green: 0.16, blue: 0.13).opacity(0.55)), lineWidth: 0.9)
    }

    /// The iris and its pupil; the pupil slides toward `look` (-1…1 each way), the shine stays put.
    private static func eye(x: Double, y: Double, r: Double, open: Double, look: CGPoint,
                            in g: inout GraphicsContext) {
        if open < 0.25 { // closed: a happy curve
            var lid = Path()
            lid.move(to: CGPoint(x: x - 2.6 * r, y: y))
            lid.addQuadCurve(to: CGPoint(x: x + 2.6 * r, y: y), control: CGPoint(x: x, y: y - 2.4 * r))
            g.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            return
        }
        let h = 3.9 * r * min(1.25, open)
        g.fill(ellipse(x, y, 2.9 * r, h), with: .color(ink))
        g.fill(ellipse(x, y - h * 0.25, 2.1 * r, h * 0.55), with: .color(iris))
        g.fill(ellipse(x + 0.3 + look.x * 0.8 * r, y + look.y * 0.6 * r, 1.2 * r, h * 0.62), with: .color(ink))
        g.fill(ellipse(x + 0.9 * r, y + h * 0.42, 1.1 * r, 1.1 * r), with: .color(.white))
        g.fill(ellipse(x - r, y - h * 0.35, 0.55 * r, 0.55 * r), with: .color(.white))
    }

    // MARK: - Helpers

    private static func capsule(_ points: [CGPoint], width: CGFloat, color: Color, in g: inout GraphicsContext) {
        var path = Path()
        path.addLines(points)
        g.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
                                rotation: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            .applying(CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation))
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// The colour moved toward black (negative) or white, like cat2d.js `shade`.
    private static func shade(_ hex: Int, _ amount: Double) -> Color {
        func move(_ v: Int) -> Double { min(1, max(0, Double(v) / 255 + amount)) }
        return Color(red: move(hex >> 16 & 0xFF), green: move(hex >> 8 & 0xFF), blue: move(hex & 0xFF))
    }
}
