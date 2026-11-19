import Foundation

// The cartoon cat from Meawki (github.com/phanumat44/Meawki, ISC licence), ported from renderer/pose.js.
// A pose is a flat record of joint angles and offsets (local space: +x forward, +y up, origin between the paws,
// units are model points). The animator eases the live pose toward the target for the current mode every frame;
// the app draws whatever the pose says.

public struct MeawkiCatPose: Sendable, Equatable {
    public var y = 0.0, sx = 1.0, sy = 1.0, pitch = 0.0
    public var neck = 0.0, headTilt = 0.0, headYaw = 0.0, eye = 1.0, ear = 0.0
    public var flh = 0.0, flk = 0.0, frh = 0.0, frk = 0.0, blh = 0.0, blk = 0.0, brh = 0.0, brk = 0.0
    public var frontScale = 1.0
    public var tailLift = 0.5, tailCurl = 0.08, tailWave = 0.15, tailSpeed = 2.0
    public var mouth = 0.0, tongue = 0.0, puff = 0.0

    public init() {}

    nonisolated(unsafe) private static let keys: [WritableKeyPath<MeawkiCatPose, Double>] = [
        \.y, \.sx, \.sy, \.pitch, \.neck, \.headTilt, \.headYaw, \.eye, \.ear,
        \.flh, \.flk, \.frh, \.frk, \.blh, \.blk, \.brh, \.brk, \.frontScale,
        \.tailLift, \.tailCurl, \.tailWave, \.tailSpeed, \.mouth, \.tongue, \.puff,
    ]

    /// This pose moved a fraction `k` of the way to `target`.
    func eased(toward target: MeawkiCatPose, by k: Double) -> MeawkiCatPose {
        Self.keys.reduce(into: self) { pose, key in pose[keyPath: key] += (target[keyPath: key] - pose[keyPath: key]) * k }
    }
}

public enum MeawkiCatMode: Sendable, Equatable {
    case idle, sit, groom, walk, run, alert, arch, dangle, fall
}

/// The cat's moving state between frames. Pure value: `advanced` returns the next one.
public struct MeawkiCat: Sendable, Equatable {
    public let pose: MeawkiCatPose
    /// Seconds since it appeared; drives breathing, tail waves and grooming.
    public let time: TimeInterval
    /// Seconds left of the current blink.
    public let blink: TimeInterval
    let nextBlink: TimeInterval
    let gaitPhase: Double
    /// -0.35 facing right … -π + 0.35 facing left; the drawing squashes through the turn.
    public let yaw: Double

    public static let start = MeawkiCat(pose: MeawkiCatPose(), time: 0, blink: 0, nextBlink: 2, gaitPhase: 0,
                                        yaw: -0.35)

    /// Which mode a mascot pose and face ask for. Resting cycles through standing, sitting and grooming.
    public static func mode(for pose: MascotPose, face: MascotFace) -> MeawkiCatMode {
        if pose.isFlying { return .fall }
        if pose.isPickedUp { return .dangle }
        if pose.isRunning || face == .fleeing { return .run }
        if pose.isWalking { return .walk }
        switch face {
        case .curious, .veryCurious: return .alert
        case .annoyed: return .arch
        case .calm, .fleeing: break
        }
        switch pose.elapsed {
        case ..<1.5: return .idle
        case 4..<5.5: return .groom
        default: return .sit
        }
    }

    /// - Parameters:
    ///   - look: how far to lift (positive) or lower the head toward the mouse, in radians.
    ///   - speed: points per second while walking or running.
    public func advanced(by dt: TimeInterval, mode: MeawkiCatMode, facesRight: Bool, look: Double = 0,
                         tilt: Double = 0, speed: Double = MascotRoute.speed) -> MeawkiCat {
        let dt = min(max(dt, 0), 0.25)
        let nextTime = time + dt
        var phase = gaitPhase
        if mode == .walk || mode == .run { phase += dt * abs(speed) * (mode == .run ? 0.055 : 0.1) }
        var target = Self.target(mode, time: nextTime, phase: phase, look: look)
        target.headTilt += tilt
        let k = 1 - exp(-dt * 12)
        let wantYaw = facesRight ? -0.35 : -Double.pi + 0.35
        var blinkLeft = max(blink - dt, 0)
        var untilBlink = nextBlink - dt
        if untilBlink < 0 {
            blinkLeft = 0.15
            // A repeatable 2…6 s gap, so the value stays testable.
            untilBlink = 2 + (sin(nextTime * 12.9898) * 43758.5453).magnitude.truncatingRemainder(dividingBy: 1) * 4
        }
        return MeawkiCat(pose: pose.eased(toward: target, by: k), time: nextTime, blink: blinkLeft,
                         nextBlink: untilBlink, gaitPhase: phase, yaw: yaw + (wantYaw - yaw) * (1 - exp(-dt * 8)))
    }

    /// Facing as a horizontal scale: 1 right, -1 left, squashed thin halfway through a turn.
    public var facing: Double {
        let u = min(1, max(0, (yaw + 0.35) / (-Double.pi + 0.7)))
        let flip = cos(u * Double.pi)
        return (flip < 0 ? -1 : 1) * max(0.18, abs(flip))
    }

    private static func sitBase(_ p: inout MeawkiCatPose) {
        p.pitch = 0.5; p.y = -18; p.frontScale = 1.12
        p.flh = -0.5; p.frh = -0.5; p.flk = 0; p.frk = 0
        p.blh = 1.35; p.brh = 1.35; p.blk = -2.2; p.brk = -2.2
        p.tailLift = -0.9; p.tailCurl = 0.22; p.tailWave = 0.08; p.tailSpeed = 1.2
    }

    // swiftlint:disable:next function_body_length
    static func target(_ mode: MeawkiCatMode, time t: Double, phase: Double, look: Double) -> MeawkiCatPose {
        var p = MeawkiCatPose()
        p.sy = 1 + sin(t * 2.2) * 0.015
        switch mode {
        case .walk, .run:
            let isRun = mode == .run
            let a = isRun ? 0.9 : 0.55
            let s = sin(phase), c = cos(phase)
            p.flh = s * a; p.brh = s * a * 0.9
            p.frh = -s * a; p.blh = -s * a * 0.9
            p.flk = -max(0, -c) * a * 1.2; p.frk = -max(0, c) * a * 1.2
            p.blk = max(0, c) * a; p.brk = max(0, -c) * a
            p.y = abs(sin(phase)) * (isRun ? 4 : 1.5) - (isRun ? 2 : 0)
            p.pitch = isRun ? sin(phase * 2) * 0.06 : 0
            p.neck = isRun ? -0.15 : 0.05
            p.tailLift = isRun ? 0.1 : 0.7
            p.tailWave = 0.1; p.tailSpeed = 6
            if isRun { p.ear = -0.8; p.eye = 1.25 }
        case .sit:
            sitBase(&p)
            p.neck = -0.45 + sin(t * 0.7) * 0.05 - look
            p.headYaw = look == 0 ? sin(t * 0.4) * 0.5 : 0
        case .groom:
            sitBase(&p)
            let lick = sin(t * 7)
            p.frh = 2.1; p.frk = 0.15 + lick * 0.2
            p.neck = 0.15 + lick * 0.08; p.headTilt = 0.25; p.eye = 0.1; p.tongue = 1; p.ear = -0.1
            p.tailWave = 0.15; p.tailSpeed = 1.5
        case .alert:
            p.neck = -0.2 - look; p.ear = 0.35; p.eye = 1.25; p.tailLift = 1.2; p.tailCurl = 0.02; p.sy = 1.04
        case .arch:
            p.y = 6 + sin(t * 40) * 0.4; p.sy = 1.12; p.sx = 0.94
            p.flh = -0.15; p.frh = -0.15; p.blh = 0.15; p.brh = 0.15
            p.neck = 0.1; p.ear = -0.9; p.eye = 1.3; p.mouth = 0.6; p.puff = 1
            p.tailLift = 1.5; p.tailCurl = -0.02; p.tailWave = 0.05; p.tailSpeed = 20
        case .dangle:
            p.pitch = -0.2; p.sy = 1.12; p.sx = 0.92
            p.flh = 0.1 + sin(t * 2) * 0.12; p.frh = 0.15 - sin(t * 2) * 0.12
            p.blh = -0.25 + sin(t * 2.3) * 0.15; p.brh = -0.15 - sin(t * 2.3) * 0.15
            p.tailLift = -1.3; p.tailCurl = 0.05; p.tailWave = 0.25; p.tailSpeed = 2; p.ear = -0.4
        case .fall:
            p.flh = 0.9; p.frh = 0.7; p.blh = -0.6; p.brh = -0.4; p.flk = -0.4; p.frk = -0.4
            p.y = 2; p.tailLift = 1.2; p.tailWave = 0.6; p.tailSpeed = 10; p.eye = 1.25; p.ear = -0.6
            p.neck = -0.2
        case .idle:
            p.neck = sin(t * 0.5) * 0.06 - look
            p.headYaw = look == 0 ? sin(t * 0.23) * 0.35 : 0
        }
        return p
    }
}
