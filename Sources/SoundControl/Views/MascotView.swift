import SwiftUI
import SoundControlCore

/// The chosen animal roaming across the screen saver: it walks, stops, breathes, blinks,
/// and can be picked up and dropped anywhere on the screen.
/// Drawn from a few shapes each frame, so it needs no images; it stops redrawing while the screen is dark.
struct MascotStroll: View {
    static let size: CGFloat = 64
    /// 24 frames a second is smooth at walking speed.
    private static let frameInterval: TimeInterval = 1.0 / 24

    let mascot: Mascot
    let isPaused: Bool

    @State private var start = Date()
    @State private var seed = UInt64.random(in: 0...UInt64.max)
    @State private var walker = Walker()
    @State private var droppedAt: CGPoint?
    @State private var dragLocation: CGPoint?
    @State private var dragStartOffset: CGSize?
    @State private var lastDragX: CGFloat?
    @State private var dragFacesRight = true

    var body: some View {
        GeometryReader { geometry in
            let maxX = max(geometry.size.width - Self.size, 0)
            let maxY = max(geometry.size.height - Self.size, 0)
            TimelineView(.animation(minimumInterval: Self.frameInterval, paused: isPaused && dragLocation == nil)) { context in
                let pose = currentPose(maxX: maxX, maxY: maxY, at: context.date)
                Canvas { graphics, size in
                    MascotArt.draw(mascot, pose: pose, in: &graphics, size: size)
                }
                .frame(width: Self.size, height: Self.size)
                .scaleEffect(x: pose.facesRight ? 1 : -1, y: 1)
                .scaleEffect(pose.isPickedUp ? 1.12 : 1.0)
                .contentShape(Rectangle())
                .pointerStyle(dragLocation != nil ? .grabActive : .grabIdle)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("mascotArea"))
                        .onChanged { value in
                            if dragStartOffset == nil {
                                dragStartOffset = CGSize(
                                    width: value.startLocation.x - CGFloat(pose.x),
                                    height: value.startLocation.y - CGFloat(pose.y)
                                )
                                dragFacesRight = pose.facesRight
                                lastDragX = value.location.x
                            }
                            if let previousX = lastDragX {
                                let deltaX = value.location.x - previousX
                                if abs(deltaX) > 1.5 {
                                    dragFacesRight = deltaX > 0
                                    lastDragX = value.location.x
                                }
                            }
                            let offset = dragStartOffset ?? .zero
                            dragLocation = clampedPoint(
                                x: value.location.x - offset.width,
                                y: value.location.y - offset.height,
                                maxX: maxX,
                                maxY: maxY
                            )
                        }
                        .onEnded { value in
                            let offset = dragStartOffset ?? .zero
                            let drop = clampedPoint(
                                x: value.location.x - offset.width,
                                y: value.location.y - offset.height,
                                maxX: maxX,
                                maxY: maxY
                            )
                            droppedAt = drop
                            dragLocation = nil
                            dragStartOffset = nil
                            lastDragX = nil
                            seed = UInt64.random(in: 0...UInt64.max)
                            start = Date()
                            walker.reset()
                        }
                )
                .position(x: CGFloat(pose.x) + Self.size / 2, y: CGFloat(pose.y) + Self.size / 2)
            }
        }
        .coordinateSpace(name: "mascotArea")
        .accessibilityHidden(true)
    }

    private func currentPose(maxX: CGFloat, maxY: CGFloat, at date: Date) -> MascotPose {
        let elapsed = date.timeIntervalSince(start)
        if let drag = dragLocation {
            let clamped = clampedPoint(x: drag.x, y: drag.y, maxX: maxX, maxY: maxY)
            return MascotPose(x: Double(clamped.x), y: Double(clamped.y),
                              facesRight: dragFacesRight, isWalking: false, isPickedUp: true,
                              steps: 0, elapsed: elapsed)
        }
        let route = MascotRoute(seed: seed, width: Double(maxX), height: Double(maxY),
                                startX: droppedAt.map { Double($0.x) },
                                startY: droppedAt.map { Double($0.y) } ?? Double(maxY))
        return walker.pose(on: route, at: elapsed)
    }

    private func clampedPoint(x: CGFloat, y: CGFloat, maxX: CGFloat, maxY: CGFloat) -> CGPoint {
        CGPoint(x: min(max(x, 0), maxX), y: min(max(y, 0), maxY))
    }

    /// Keeps the route's cursor between frames, so each frame starts from the current leg.
    /// Not observed: changing it must not trigger a redraw of its own.
    private final class Walker {
        private var cursor = MascotRoute.Cursor.origin

        func pose(on route: MascotRoute, at time: TimeInterval) -> MascotPose {
            let (pose, next) = route.pose(at: time, from: cursor)
            cursor = next
            return pose
        }

        func reset() {
            cursor = .origin
        }
    }
}

/// Draws each animal facing right in a 72 × 72 box: feet, tail, body, head, ears, face.
enum MascotArt {
    private static let canvas: CGFloat = 72
    private static let eyeColor = Color(red: 0.16, green: 0.12, blue: 0.16)
    private static let blush = Color(red: 1, green: 0.55, blue: 0.62).opacity(0.65)
    private static let blinkPeriod: TimeInterval = 3.7
    private static let blinkLength: TimeInterval = 0.14

    private struct Look {
        let fur: Color
        let belly: Color
        let feet: Color
    }

    /// The parts that move: the step cycle, the bounce, pickup dangle, and the blink.
    private struct Motion {
        let swing: CGFloat
        let lift: CGFloat
        let bob: CGFloat
        let isBlinking: Bool
        let isPickedUp: Bool
        let time: TimeInterval

        init(_ pose: MascotPose) {
            isPickedUp = pose.isPickedUp
            if pose.isPickedUp {
                swing = CGFloat(sin(pose.elapsed * 18)) * 1.1
                lift = 1.0
                bob = -5 + CGFloat(sin(pose.elapsed * 8)) * 1.2
                isBlinking = false
            } else {
                let cycle = pose.steps * 2 * .pi
                swing = pose.isWalking ? CGFloat(sin(cycle)) : 0
                lift = pose.isWalking ? CGFloat(abs(sin(cycle))) : 0
                bob = pose.isWalking ? -lift * 2.5 : CGFloat(sin(pose.elapsed * 2.2)) * 0.6
                isBlinking = pose.elapsed.truncatingRemainder(dividingBy: MascotArt.blinkPeriod) < MascotArt.blinkLength
            }
            time = pose.elapsed
        }
    }

    static func draw(_ mascot: Mascot, pose: MascotPose, in graphics: inout GraphicsContext, size: CGSize) {
        guard mascot != .none else { return }
        graphics.scaleBy(x: size.width / canvas, y: size.height / canvas)
        let motion = Motion(pose)
        drawShadow(motion, in: &graphics)
        if mascot == .penguin, pose.isWalking || pose.isPickedUp {
            // Penguins waddle: the whole body rocks around the feet.
            graphics.translateBy(x: 34, y: 66)
            graphics.rotate(by: .degrees(Double(motion.swing) * 6))
            graphics.translateBy(x: -34, y: -66)
        }
        let look = look(mascot)
        drawFeet(look, motion, in: &graphics)
        drawTail(mascot, look, motion, in: &graphics)
        drawBody(mascot, look, motion, in: &graphics)
        drawEars(mascot, look, motion, in: &graphics)
        drawHead(mascot, look, motion, in: &graphics)
        drawFace(mascot, pose, motion, in: &graphics)
    }

    private static func look(_ mascot: Mascot) -> Look {
        switch mascot {
        case .none, .cat:
            Look(fur: Color(red: 1, green: 0.72, blue: 0.42), belly: Color(red: 1, green: 0.93, blue: 0.83),
                 feet: Color(red: 1, green: 0.93, blue: 0.83))
        case .puppy:
            Look(fur: Color(red: 0.91, green: 0.76, blue: 0.56), belly: Color(red: 1, green: 0.95, blue: 0.86),
                 feet: Color(red: 1, green: 0.95, blue: 0.86))
        case .bunny:
            Look(fur: Color(red: 0.97, green: 0.95, blue: 0.98), belly: .white, feet: .white)
        case .panda:
            Look(fur: Color(red: 0.97, green: 0.97, blue: 0.96), belly: .white, feet: Color(red: 0.18, green: 0.17, blue: 0.2))
        case .penguin:
            Look(fur: Color(red: 0.2, green: 0.25, blue: 0.38), belly: .white, feet: Color(red: 1, green: 0.66, blue: 0.25))
        }
    }

    // MARK: - Parts

    private static func drawShadow(_ motion: Motion, in graphics: inout GraphicsContext) {
        let shadow = motion.isPickedUp
            ? CGRect(x: 23, y: 65, width: 24, height: 4)
            : CGRect(x: 18, y: 63, width: 34, height: 6)
        graphics.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(motion.isPickedUp ? 0.16 : 0.28)))
    }

    private static func drawFeet(_ look: Look, _ motion: Motion, in graphics: inout GraphicsContext) {
        let footDrop: CGFloat = motion.isPickedUp ? -3 : 0
        let back = CGRect(x: 21 + motion.swing * 3, y: 61 + footDrop - max(motion.swing, 0) * 2, width: 10, height: 7)
        let front = CGRect(x: 37 - motion.swing * 3, y: 61 + footDrop - max(-motion.swing, 0) * 2, width: 10, height: 7)
        graphics.fill(Path(ellipseIn: back), with: .color(look.feet))
        graphics.fill(Path(ellipseIn: front), with: .color(look.feet))
    }

    private static func drawTail(_ mascot: Mascot, _ look: Look, _ motion: Motion, in graphics: inout GraphicsContext) {
        let sway = CGFloat(sin(motion.time * 3)) * 3
        let wag = CGFloat(sin(motion.time * 12)) * 3
        switch mascot {
        case .cat:
            var tail = Path()
            tail.move(to: CGPoint(x: 17, y: 52 + motion.bob))
            tail.addQuadCurve(to: CGPoint(x: 8 + sway, y: 34 + motion.bob), control: CGPoint(x: 4, y: 50))
            graphics.stroke(tail, with: .color(look.fur), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        case .puppy:
            var tail = Path()
            tail.move(to: CGPoint(x: 17, y: 50 + motion.bob))
            tail.addLine(to: CGPoint(x: 10 + wag, y: 42 + motion.bob))
            graphics.stroke(tail, with: .color(look.fur), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        case .bunny:
            graphics.fill(Path(ellipseIn: CGRect(x: 11, y: 46 + motion.bob, width: 9, height: 9)), with: .color(.white))
        case .panda:
            graphics.fill(Path(ellipseIn: CGRect(x: 13, y: 48 + motion.bob, width: 7, height: 7)), with: .color(look.fur))
        case .penguin, .none:
            break
        }
    }

    private static func drawBody(_ mascot: Mascot, _ look: Look, _ motion: Motion, in graphics: inout GraphicsContext) {
        let isPenguin = mascot == .penguin
        let body = isPenguin ? CGRect(x: 18, y: 34 + motion.bob, width: 32, height: 30)
                             : CGRect(x: 15, y: 42 + motion.bob, width: 36, height: 22)
        graphics.fill(Path(ellipseIn: body), with: .color(look.fur))
        let belly = isPenguin ? CGRect(x: 25, y: 39 + motion.bob, width: 20, height: 23)
                              : CGRect(x: 26, y: 48 + motion.bob, width: 19, height: 14)
        graphics.fill(Path(ellipseIn: belly), with: .color(look.belly))
        if isPenguin {
            // A little wing that flaps while it waddles.
            var wing = graphics
            wing.translateBy(x: 22, y: 42 + motion.bob)
            wing.rotate(by: .degrees(20 + Double(motion.lift) * 18))
            wing.fill(Path(ellipseIn: CGRect(x: -4, y: 0, width: 8, height: 17)), with: .color(look.fur.opacity(0.9)))
        }
    }

    private static func drawEars(_ mascot: Mascot, _ look: Look, _ motion: Motion, in graphics: inout GraphicsContext) {
        let pink = Color(red: 1, green: 0.7, blue: 0.75)
        let y = motion.bob
        switch mascot {
        case .cat:
            graphics.fill(triangle(CGPoint(x: 27, y: 20 + y), CGPoint(x: 30, y: 6 + y), CGPoint(x: 38, y: 15 + y)), with: .color(look.fur))
            graphics.fill(triangle(CGPoint(x: 44, y: 15 + y), CGPoint(x: 51, y: 6 + y), CGPoint(x: 54, y: 20 + y)), with: .color(look.fur))
            graphics.fill(triangle(CGPoint(x: 29.5, y: 17 + y), CGPoint(x: 31, y: 10 + y), CGPoint(x: 35, y: 15 + y)), with: .color(pink))
            graphics.fill(triangle(CGPoint(x: 46.5, y: 15 + y), CGPoint(x: 50, y: 10 + y), CGPoint(x: 51.5, y: 17 + y)), with: .color(pink))
        case .bunny:
            let flop = CGFloat(sin(motion.time * 2)) * 1.5
            for x in [30.0, 43.0] {
                graphics.fill(Path(ellipseIn: CGRect(x: x, y: 0 + y + flop, width: 9, height: 22)), with: .color(look.fur))
                graphics.fill(Path(ellipseIn: CGRect(x: x + 2.5, y: 4 + y + flop, width: 4, height: 14)), with: .color(pink))
            }
        case .panda:
            graphics.fill(Path(ellipseIn: CGRect(x: 24, y: 10 + y, width: 11, height: 11)), with: .color(look.feet))
            graphics.fill(Path(ellipseIn: CGRect(x: 47, y: 10 + y, width: 11, height: 11)), with: .color(look.feet))
        case .puppy, .penguin, .none:
            break
        }
    }

    private static func drawHead(_ mascot: Mascot, _ look: Look, _ motion: Motion, in graphics: inout GraphicsContext) {
        let head = CGRect(x: 24, y: 13 + motion.bob, width: 34, height: 30)
        graphics.fill(Path(ellipseIn: head), with: .color(look.fur))
        switch mascot {
        case .puppy:
            // Floppy ears hang over the sides of the head.
            let ear = Color(red: 0.62, green: 0.44, blue: 0.3)
            let flap = CGFloat(sin(motion.time * 4)) * 1.2
            graphics.fill(Path(ellipseIn: CGRect(x: 20, y: 15 + motion.bob + flap, width: 10, height: 19)), with: .color(ear))
            graphics.fill(Path(ellipseIn: CGRect(x: 52, y: 15 + motion.bob - flap, width: 10, height: 19)), with: .color(ear))
        case .penguin:
            graphics.fill(Path(ellipseIn: CGRect(x: 30, y: 19 + motion.bob, width: 24, height: 20)), with: .color(look.belly))
        case .panda:
            graphics.fill(Path(ellipseIn: CGRect(x: 32, y: 22 + motion.bob, width: 8, height: 10)), with: .color(look.feet))
            graphics.fill(Path(ellipseIn: CGRect(x: 44, y: 22 + motion.bob, width: 8, height: 10)), with: .color(look.feet))
        case .cat, .bunny, .none:
            break
        }
    }

    private static func drawFace(_ mascot: Mascot, _ pose: MascotPose, _ motion: Motion, in graphics: inout GraphicsContext) {
        let y = motion.bob
        let eyeHeight: CGFloat = motion.isBlinking ? 0.9 : 4.6
        let eyeColor = mascot == .panda ? Color.white : Self.eyeColor
        for x in [34.5, 46.0] {
            graphics.fill(Path(ellipseIn: CGRect(x: x, y: 27 + y + (4.6 - eyeHeight) / 2, width: 3.8, height: eyeHeight)),
                          with: .color(eyeColor))
            if !motion.isBlinking, mascot != .panda {
                graphics.fill(Path(ellipseIn: CGRect(x: x + 1.9, y: 27.6 + y, width: 1.3, height: 1.3)), with: .color(.white))
            }
        }
        graphics.fill(Path(ellipseIn: CGRect(x: 30, y: 33 + y, width: 6, height: 3.4)), with: .color(blush))
        graphics.fill(Path(ellipseIn: CGRect(x: 48, y: 33 + y, width: 6, height: 3.4)), with: .color(blush))

        switch mascot {
        case .penguin:
            graphics.fill(triangle(CGPoint(x: 39, y: 32 + y), CGPoint(x: 45, y: 32 + y), CGPoint(x: 42, y: 36 + y)),
                          with: .color(Color(red: 1, green: 0.66, blue: 0.25)))
        case .puppy, .panda:
            graphics.fill(Path(ellipseIn: CGRect(x: 39.5, y: 32 + y, width: 5, height: 3.4)), with: .color(Self.eyeColor))
            if motion.isPickedUp {
                graphics.fill(Path(ellipseIn: CGRect(x: 40.3, y: 35.2 + y, width: 3.4, height: 3.8)), with: .color(Self.eyeColor))
            } else {
                drawMouth(at: CGPoint(x: 42, y: 35.5 + y), in: &graphics)
            }
            if mascot == .puppy, pose.isWalking {
                graphics.fill(Path(ellipseIn: CGRect(x: 40.5, y: 36.5 + y, width: 3.4, height: 3.6)),
                              with: .color(Color(red: 1, green: 0.5, blue: 0.55)))
            }
        case .cat, .bunny:
            graphics.fill(triangle(CGPoint(x: 40.5, y: 32.5 + y), CGPoint(x: 43.5, y: 32.5 + y), CGPoint(x: 42, y: 34.5 + y)),
                          with: .color(Color(red: 1, green: 0.5, blue: 0.6)))
            if motion.isPickedUp {
                graphics.fill(Path(ellipseIn: CGRect(x: 40.3, y: 34.8 + y, width: 3.4, height: 3.8)), with: .color(Self.eyeColor))
            } else {
                drawMouth(at: CGPoint(x: 42, y: 34.5 + y), in: &graphics)
            }
            if mascot == .cat { drawWhiskers(y: y, in: &graphics) }
        case .none:
            break
        }
    }

    /// A small "w" smile under the nose.
    private static func drawMouth(at point: CGPoint, in graphics: inout GraphicsContext) {
        var mouth = Path()
        mouth.move(to: CGPoint(x: point.x - 2.6, y: point.y + 0.6))
        mouth.addQuadCurve(to: point, control: CGPoint(x: point.x - 1.3, y: point.y + 2.4))
        mouth.addQuadCurve(to: CGPoint(x: point.x + 2.6, y: point.y + 0.6), control: CGPoint(x: point.x + 1.3, y: point.y + 2.4))
        graphics.stroke(mouth, with: .color(Self.eyeColor), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
    }

    private static func drawWhiskers(y: CGFloat, in graphics: inout GraphicsContext) {
        var whiskers = Path()
        for (start, end) in [((29.0, 33.0), (22.0, 31.5)), ((29.0, 35.0), (22.0, 36.0)),
                             ((55.0, 33.0), (62.0, 31.5)), ((55.0, 35.0), (62.0, 36.0))] {
            whiskers.move(to: CGPoint(x: start.0, y: start.1 + y))
            whiskers.addLine(to: CGPoint(x: end.0, y: end.1 + y))
        }
        graphics.stroke(whiskers, with: .color(Self.eyeColor.opacity(0.55)), lineWidth: 0.7)
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: c)
        path.closeSubpath()
        return path
    }
}
