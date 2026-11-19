import Foundation

public struct MascotPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = MascotPoint(x: 0, y: 0)
}

public struct MascotColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

/// One eye in a rendered frame, in frame pixels from the top-left. Only the white or iris is rendered:
/// the app draws the pupil on top, so it can follow the mouse.
public struct MascotEyeSpot: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let radius: Double
    /// False when the head hides this eye from the camera.
    public let isVisible: Bool
}

public struct MascotFrameSpots: Sendable, Equatable {
    /// The eye on the camera side.
    public let near: MascotEyeSpot
    public let far: MascotEyeSpot
    /// Just above the head: where a question mark or an anger mark goes.
    public let headTop: MascotPoint
}

public enum MascotPupilShape: Sendable {
    case round
    /// A cat's tall pupil; it opens up round when the cat is curious.
    case slit
}

/// How one animal's sprite sheet is laid out: which frame shows which moment, and where its eyes are in each.
/// Sheets come from `Art/mascots/build_mascots.py`; the numbers in `MascotSpriteData.swift` come with them.
public struct MascotSpriteLayout: Sendable {
    public static let framePixels = 160
    public static let columns = 8
    public static let rows = 6
    /// The floor line in frame pixels, the same in every sheet.
    public static let floorY: Double = 144

    public enum Clip: Sendable, CaseIterable {
        case walk, run, idle, held, fly

        public var frameCount: Int {
            switch self {
            case .walk: 16
            case .run: 8
            case .idle: 12
            case .held: 6
            case .fly: 4
            }
        }

        /// Index of the clip's first frame in the sheet; clips follow each other in `allCases` order.
        public var firstFrame: Int {
            Self.allCases.prefix { $0 != self }.reduce(0) { $0 + $1.frameCount }
        }

        /// Frames a second for the clips that play by time rather than by distance walked.
        var rate: Double {
            switch self {
            case .idle: 8
            case .held, .fly: 10
            case .walk, .run: 0
            }
        }
    }

    public let lidColor: MascotColor
    public let pupil: MascotPupilShape
    /// Points walked during one full walk cycle at the shown size, so the feet do not slide.
    public let walkStride: Double
    public let runStride: Double
    /// Where the feet meet the floor, in frame pixels from the left, when facing right.
    public let floorX: Double
    public let frames: [MascotFrameSpots]

    public static func forMascot(_ mascot: Mascot) -> MascotSpriteLayout? {
        switch mascot {
        case .pig: .pig
        case .panda: .panda
        case .hippo: .hippo
        case .none, .cat, .puppy, .bunny, .penguin: nil
        }
    }

    public static func clip(for pose: MascotPose) -> Clip {
        if pose.isFlying { return .fly }
        if pose.isPickedUp { return .held }
        if pose.isRunning { return .run }
        return pose.isWalking ? .walk : .idle
    }

    /// The sheet frame to show for this pose.
    public func frame(for pose: MascotPose) -> Int {
        let clip = Self.clip(for: pose)
        let progress: Double
        switch clip {
        case .walk: progress = pose.steps * MascotRoute.stepLength / walkStride
        case .run: progress = pose.steps * MascotRoute.stepLength / runStride
        case .idle, .held, .fly: progress = max(pose.elapsed, 0) * clip.rate / Double(clip.frameCount)
        }
        let fraction = progress - progress.rounded(.down)
        let local = min(Int(fraction * Double(clip.frameCount)), clip.frameCount - 1)
        return clip.firstFrame + max(local, 0)
    }
}

/// Everything that changes how a sprite mascot looks. The app redraws only when this changes, so a resting mascot
/// redraws about eight times a second and a still mouse costs nothing.
public struct MascotSpriteState: Sendable, Equatable {
    public let mascot: Mascot
    public let frame: Int
    public let facesRight: Bool
    public let face: MascotFace
    public let isBlinking: Bool
    /// Where the pupils sit, as a fraction of the eye's radius, in screen directions (x right, y down).
    public let gaze: MascotPoint
    public let isOnFloor: Bool

    static let blinkPeriod: TimeInterval = 3.7
    static let blinkLength: TimeInterval = 0.14
    /// The pupils reach this far from the centre of the eye, as a fraction of its radius.
    static let gazeReach: Double = 0.45
    /// Closer than this, in points, the pupils look less far, so they do not jump when the mouse is over the face.
    static let nearDistance: Double = 40
    /// Gaze is kept in steps of this fraction, so small mouse moves do not redraw.
    static let gazeStep: Double = 0.05

    public init(mascot: Mascot, layout: MascotSpriteLayout, pose: MascotPose, face: MascotFace,
                lookingAt target: MascotPoint?, viewSize: Double) {
        let frame = layout.frame(for: pose)
        self.mascot = mascot
        self.frame = frame
        self.facesRight = pose.facesRight
        self.face = face
        self.isOnFloor = !pose.isPickedUp && !pose.isFlying
        let canBlink = face == .calm || face == .curious
        self.isBlinking = canBlink && pose.elapsed.truncatingRemainder(dividingBy: Self.blinkPeriod) < Self.blinkLength
        let eye = Self.eyeCenter(layout.frames[frame].near, facesRight: pose.facesRight, viewSize: viewSize)
        self.gaze = Self.gaze(from: eye, to: target, facesRight: pose.facesRight)
    }

    /// An eye's centre in view points (top-left origin), mirrored when the animal faces left.
    public static func eyeCenter(_ spot: MascotEyeSpot, facesRight: Bool, viewSize: Double) -> MascotPoint {
        viewPoint(MascotPoint(x: spot.x, y: spot.y), facesRight: facesRight, viewSize: viewSize)
    }

    /// A point in frame pixels, in view points (top-left origin), mirrored when the animal faces left.
    public static func viewPoint(_ point: MascotPoint, facesRight: Bool, viewSize: Double) -> MascotPoint {
        let scale = viewSize / Double(MascotSpriteLayout.framePixels)
        let x = facesRight ? point.x : Double(MascotSpriteLayout.framePixels) - point.x
        return MascotPoint(x: x * scale, y: point.y * scale)
    }

    /// Pupils turn toward the target; with no target they look ahead.
    public static func gaze(from eye: MascotPoint, to target: MascotPoint?, facesRight: Bool) -> MascotPoint {
        guard let target else { return MascotPoint(x: facesRight ? 0.3 : -0.3, y: 0.05) }
        let dx = target.x - eye.x
        let dy = target.y - eye.y
        let distance = hypot(dx, dy)
        guard distance > 0.5 else { return .zero }
        let reach = gazeReach * min(distance / nearDistance, 1)
        return MascotPoint(x: quantized(dx / distance * reach), y: quantized(dy / distance * reach))
    }

    private static func quantized(_ value: Double) -> Double {
        (value / gazeStep).rounded() * gazeStep
    }
}
