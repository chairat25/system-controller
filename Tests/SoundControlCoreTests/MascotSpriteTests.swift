import Foundation
import Testing
@testable import SoundControlCore

@Suite("Mascot mood")
struct MascotMoodTests {
    @Test("first click is curious, second more curious, then annoyed, and the sixth makes it run")
    func buildsUp() {
        var mood = MascotMood.calm
        var faces: [MascotFace] = []
        for click in 0..<6 {
            mood = mood.poked(at: Double(click))
            faces.append(mood.face(at: Double(click)))
        }
        #expect(faces == [.curious, .veryCurious, .annoyed, .annoyed, .annoyed, .fleeing])
        #expect(mood.wantsToFlee)
    }

    @Test("a slow click starts over, and the face fades when left alone")
    func calmsDown() {
        let twice = MascotMood.calm.poked(at: 0).poked(at: 1)
        #expect(twice.face(at: 1) == .veryCurious)
        #expect(twice.face(at: 1 + MascotMood.faceDuration) == .calm)
        let later = twice.poked(at: 1 + MascotMood.streakGap + 0.1)
        #expect(later.clicks == 1)
        #expect(later.face(at: 1 + MascotMood.streakGap + 0.1) == .curious)
        #expect(MascotMood.calm.face(at: 100) == .calm)
        #expect(!MascotMood.calm.wantsToFlee)
    }
}

@Suite("Mascot sprite")
struct MascotSpriteTests {
    private let pig = MascotSpriteLayout.pig

    @Test("every sprite sheet has one entry per frame and fits the sheet")
    func sheetsAreComplete() throws {
        let total = MascotSpriteLayout.Clip.allCases.reduce(0) { $0 + $1.frameCount }
        #expect(total <= MascotSpriteLayout.columns * MascotSpriteLayout.rows)
        for mascot in [Mascot.pig, .panda, .hippo, .tabby] {
            let layout = try #require(MascotSpriteLayout.forMascot(mascot))
            #expect(layout.frames.count == total)
            #expect(layout.walkStride > 0 && layout.runStride > layout.walkStride)
            #expect(layout.frames.allSatisfy { $0.near.isVisible && $0.near.radius > 0 })
        }
        #expect(MascotSpriteLayout.forMascot(.penguin) == nil)
        #expect(MascotSpriteLayout.forMascot(.cat) == nil)
    }

    @Test("clips follow each other in the sheet")
    func clipOrder() {
        #expect(MascotSpriteLayout.Clip.walk.firstFrame == 0)
        #expect(MascotSpriteLayout.Clip.run.firstFrame == 16)
        #expect(MascotSpriteLayout.Clip.idle.firstFrame == 24)
        #expect(MascotSpriteLayout.Clip.held.firstFrame == 36)
        #expect(MascotSpriteLayout.Clip.fly.firstFrame == 42)
    }

    @Test("the pose picks the clip: flying, held, running, walking, resting")
    func picksClip() {
        func pose(walking: Bool = false, held: Bool = false, running: Bool = false, flying: Bool = false) -> MascotPose {
            MascotPose(x: 0, facesRight: true, isWalking: walking, isPickedUp: held || flying, isRunning: running,
                       isFlying: flying, steps: 0, elapsed: 0)
        }
        #expect(MascotSpriteLayout.clip(for: pose(flying: true)) == .fly)
        #expect(MascotSpriteLayout.clip(for: pose(held: true)) == .held)
        #expect(MascotSpriteLayout.clip(for: pose(walking: true, running: true)) == .run)
        #expect(MascotSpriteLayout.clip(for: pose(walking: true)) == .walk)
        #expect(MascotSpriteLayout.clip(for: pose()) == .idle)
    }

    @Test("walk frames follow the distance walked, so one stride is one cycle")
    func walkFollowsDistance() {
        func frame(walked points: Double) -> Int {
            pig.frame(for: MascotPose(x: 0, facesRight: true, isWalking: true,
                                      steps: points / MascotRoute.stepLength, elapsed: 0))
        }
        #expect(frame(walked: 0) == 0)
        #expect(frame(walked: pig.walkStride / 2) == 8)
        #expect(frame(walked: pig.walkStride * 3 + 0.01) == 0)
        #expect((0..<16).contains(frame(walked: 12_345.6)))
    }

    @Test("resting frames play by time and stay inside the idle clip")
    func idleByTime() {
        let idle = MascotSpriteLayout.Clip.idle
        let frames = stride(from: 0.0, to: 10, by: 0.07).map {
            pig.frame(for: MascotPose(x: 0, facesRight: true, isWalking: false, steps: 0, elapsed: $0))
        }
        #expect(frames.allSatisfy { (idle.firstFrame..<idle.firstFrame + idle.frameCount).contains($0) })
        #expect(Set(frames).count == idle.frameCount)
    }

    @Test("eyes mirror when facing left")
    func mirrorsEyes() {
        let spot = MascotEyeSpot(x: 120, y: 40, radius: 6, isVisible: true)
        let right = MascotSpriteState.eyeCenter(spot, facesRight: true, viewSize: 80)
        let left = MascotSpriteState.eyeCenter(spot, facesRight: false, viewSize: 80)
        #expect(right == MascotPoint(x: 60, y: 20))
        #expect(left == MascotPoint(x: 20, y: 20))
    }

    @Test("pupils turn toward the mouse, reach no further than the edge, and look ahead without one")
    func gaze() {
        let eye = MascotPoint(x: 50, y: 20)
        let far = MascotSpriteState.gaze(from: eye, to: MascotPoint(x: 1050, y: 20), facesRight: true)
        #expect(far == MascotPoint(x: MascotSpriteState.gazeReach, y: 0))
        let up = MascotSpriteState.gaze(from: eye, to: MascotPoint(x: 50, y: -500), facesRight: true)
        #expect(up.y < 0 && up.x == 0)
        let close = MascotSpriteState.gaze(from: eye, to: MascotPoint(x: 60, y: 20), facesRight: true)
        #expect(close.x > 0 && close.x < far.x)
        let ahead = MascotSpriteState.gaze(from: eye, to: nil, facesRight: false)
        #expect(ahead.x < 0)
    }

    @Test("small mouse moves far away do not change the state")
    func steadyState() {
        let pose = MascotPose(x: 0, facesRight: true, isWalking: false, steps: 0, elapsed: 1)
        let first = MascotSpriteState(mascot: .pig, layout: pig, pose: pose, face: .calm,
                                      lookingAt: MascotPoint(x: 900, y: 300), viewSize: 80)
        let second = MascotSpriteState(mascot: .pig, layout: pig, pose: pose, face: .calm,
                                       lookingAt: MascotPoint(x: 903, y: 301), viewSize: 80)
        #expect(first == second)
    }

    @Test("annoyed and running faces do not blink; held and flying are off the floor")
    func blinkAndFloor() {
        let blinkTime = MascotPose(x: 0, facesRight: true, isWalking: false, steps: 0, elapsed: 0.05)
        let calm = MascotSpriteState(mascot: .pig, layout: pig, pose: blinkTime, face: .calm, lookingAt: nil, viewSize: 80)
        let annoyed = MascotSpriteState(mascot: .pig, layout: pig, pose: blinkTime, face: .annoyed, lookingAt: nil,
                                        viewSize: 80)
        #expect(calm.isBlinking && calm.isOnFloor)
        #expect(!annoyed.isBlinking)
        let held = MascotPose(x: 0, facesRight: true, isWalking: false, isPickedUp: true, steps: 0, elapsed: 1)
        #expect(!MascotSpriteState(mascot: .pig, layout: pig, pose: held, face: .calm, lookingAt: nil,
                                   viewSize: 80).isOnFloor)
    }
}

@Suite("Running away")
struct MascotFleeTests {
    private func walker() -> RoamingWalker {
        RoamingWalker.landed(id: "a", x: 500, facesRight: true, seed: 1)
    }

    @Test("runs away from the mouse, faster than a walk, then stops to rest")
    func fleesAndRests() {
        let scared = walker().fleeing(from: 700, size: 80)
        #expect(scared.isRunning && scared.isWalking && !scared.facesRight)
        #expect(scared.pose.isRunning)
        let (moved, _) = scared.advanced(by: 0.1, maxX: 1000, size: 80, canExit: { _ in false })
        #expect(moved.x < 500 - MascotRoute.speed * 0.1 * 2)
        var current = moved
        for _ in 0..<40 {
            current = current.advanced(by: 0.1, maxX: 1000, size: 80, canExit: { _ in false }).walker
        }
        #expect(!current.isRunning)
    }

    @Test("a cornered runner stops at the wall instead of turning back toward the mouse")
    func cornered() {
        let scared = RoamingWalker.landed(id: "a", x: 10, facesRight: true, seed: 1).fleeing(from: 60, size: 80)
        #expect(!scared.facesRight)
        let (stopped, handoff) = scared.advanced(by: 0.2, maxX: 1000, size: 80, canExit: { _ in false })
        #expect(handoff == nil)
        #expect(stopped.x == 0 && !stopped.isRunning && !stopped.isWalking)
    }

    @Test("a runner can run off to a neighbour")
    func runsAcross() {
        var current = RoamingWalker.landed(id: "a", x: 10, facesRight: true, seed: 1).fleeing(from: 60, size: 80)
        var handoff: RoamingObject?
        for _ in 0..<30 where handoff == nil {
            (current, handoff) = current.advanced(by: 0.05, maxX: 1000, size: 80, canExit: { $0 == .left })
        }
        #expect(handoff?.direction == .left)
    }
}

@Suite("Roaming look")
struct RoamingLookTests {
    @Test("an animal this Mac does not know arrives with no look instead of failing")
    func unknownLook() throws {
        let json = #"{"id":"abc","kind":"mascot","yFraction":1,"direction":"left","state":"walking","look":"dragon"}"#
        let object = try JSONDecoder().decode(RoamingObject.self, from: Data(json.utf8))
        #expect(object.look == nil)
        let pig = RoamingObject(id: "abc", kind: .mascot, yFraction: 1, direction: .left, state: .walking, look: .pig)
        let decoded = try JSONDecoder().decode(RoamingObject.self, from: JSONEncoder().encode(pig))
        #expect(decoded == pig)
    }
}

@Suite("Cartoon cat")
struct MeawkiCatTests {
    private func pose(walk: Bool = false, run: Bool = false, held: Bool = false, fly: Bool = false,
                      elapsed: Double = 0) -> MascotPose {
        MascotPose(x: 0, facesRight: true, isWalking: walk || run, isPickedUp: held || fly, isRunning: run,
                   isFlying: fly, steps: 0, elapsed: elapsed)
    }

    @Test("the mascot pose and face pick the cat's mode")
    func modes() {
        #expect(MeawkiCat.mode(for: pose(fly: true), face: .calm) == .fall)
        #expect(MeawkiCat.mode(for: pose(held: true), face: .annoyed) == .dangle)
        #expect(MeawkiCat.mode(for: pose(run: true), face: .calm) == .run)
        #expect(MeawkiCat.mode(for: pose(walk: true), face: .curious) == .walk)
        #expect(MeawkiCat.mode(for: pose(), face: .curious) == .alert)
        #expect(MeawkiCat.mode(for: pose(), face: .annoyed) == .arch)
        #expect(MeawkiCat.mode(for: pose(elapsed: 0.5), face: .calm) == .idle)
        #expect(MeawkiCat.mode(for: pose(elapsed: 2.5), face: .calm) == .sit)
        #expect(MeawkiCat.mode(for: pose(elapsed: 4.5), face: .calm) == .groom)
    }

    @Test("easing reaches the target pose and turning flips the facing")
    func eases() {
        var cat = MeawkiCat.start
        for _ in 0..<120 { cat = cat.advanced(by: 1.0 / 24, mode: .arch, facesRight: false) }
        #expect(abs(cat.pose.puff - 1) < 0.01)
        #expect(abs(cat.pose.ear + 0.9) < 0.01)
        #expect(cat.facing == -1)
        #expect(MeawkiCat.start.facing == 1)
    }

    @Test("walking moves the legs, and the cat blinks every few seconds")
    func walksAndBlinks() {
        var cat = MeawkiCat.start
        var legs = Set<Int>()
        var blinked = false
        for _ in 0..<(24 * 7) {
            cat = cat.advanced(by: 1.0 / 24, mode: .walk, facesRight: true)
            legs.insert(Int((cat.pose.flh * 10).rounded()))
            blinked = blinked || cat.blink > 0
        }
        #expect(legs.count > 5)
        #expect(blinked)
    }

    @Test("a long pause between frames does not jump the pose")
    func clampsLongGap() {
        let cat = MeawkiCat.start.advanced(by: 30, mode: .arch, facesRight: true)
        #expect(cat.time == 0.25)
    }
}
