import CryptoKit
import Foundation
import Testing
@testable import SoundControlCore

@Suite("LAN sync settings")
struct LANSyncSettingsTests {
    private let mac = PairedPeer(id: "A1", name: "Studio", side: .left)

    @Test("defaults share nothing and are inactive")
    func defaults() {
        let settings = LANSyncSettings.default
        #expect(!settings.isActive)
        #expect(settings.pairedPeers.isEmpty)
    }

    @Test("round trips through JSON")
    func roundTrip() throws {
        let settings = LANSyncSettings.default.withWallpaperSync(true).adding(mac)
        let decoded = try JSONDecoder().decode(LANSyncSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test("a bad field or peer falls back instead of failing the file")
    func lossyDecoding() throws {
        let json = #"{"isWallpaperSyncOn":"yes","isMascotRoamingOn":true,"pairedPeers":[{"id":"ok","name":"B","side":"up"},{"id":"bad id"},{"name":"x"}]}"#
        let decoded = try JSONDecoder().decode(LANSyncSettings.self, from: Data(json.utf8))
        #expect(!decoded.isWallpaperSyncOn)
        #expect(decoded.isMascotRoamingOn)
        #expect(decoded.pairedPeers == [PairedPeer(id: "ok", name: "B", side: .right)])
    }

    @Test("adding a known peer keeps its side, removing forgets it")
    func addRemove() {
        let moved = LANSyncSettings.default.adding(mac).withSide(.right, for: "A1")
        let renamed = moved.adding(PairedPeer(id: "A1", name: "New", side: .left))
        #expect(renamed.pairedPeers == [PairedPeer(id: "A1", name: "New", side: .right)])
        #expect(renamed.peer(on: .right)?.id == "A1")
        #expect(renamed.peer(on: .left) == nil)
        #expect(renamed.removing("A1").pairedPeers.isEmpty)
    }

    @Test("either toggle makes sync active")
    func activity() {
        #expect(LANSyncSettings.default.withMascotRoaming(true).isActive)
        #expect(LANSyncSettings.default.withWallpaperSync(true).isActive)
    }
}

@Suite("Sync messages and framing")
struct SyncMessageTests {
    @Test("every message round trips")
    func roundTrip() throws {
        let meta = WallpaperMeta(kind: .desktop, timestamp: 1_700_000_000, fileName: "sea.jpg", size: 1234)
        let object = RoamingObject(id: "m1", kind: .mascot, yFraction: 0.9, direction: .right, state: .walking)
        let messages: [SyncMessage] = [
            .hello(deviceID: "A", name: "Mac", wantsWallpaper: true, wantsRoaming: false),
            .pairCommit(deviceID: "A", name: "Mac", commitment: Data([1, 2])),
            .pairKey(deviceID: "B", name: "Mac", publicKey: Data([3])),
            .pairReveal(publicKey: Data([4])), .pairConfirm, .pairCancel,
            .wallpaperOffer(meta), .wallpaperRequest(kind: .screenSaver, timestamp: 5), .wallpaperData(meta),
            .roamingHandoff(object)
        ]
        for message in messages {
            #expect(try SyncMessage.decode(message.encoded()) == message)
        }
    }

    @Test("a file name cannot climb out of a folder")
    func cleanFileName() {
        #expect(WallpaperMeta.cleanFileName("../../etc/passwd") == "passwd")
        #expect(WallpaperMeta.cleanFileName("..\\x\\.hidden.png") == "hidden.png")
        #expect(WallpaperMeta.cleanFileName("") == "wallpaper")
        #expect(WallpaperMeta.cleanFileName("a\nb.jpg") == "ab.jpg")
    }

    @Test("frames split across reads and joined in one read both decode")
    func framing() throws {
        let first = SyncFraming.encode(kind: .message, payload: Data("one".utf8))
        let second = SyncFraming.encode(kind: .raw, payload: Data(repeating: 7, count: 300))
        let stream = first + second
        var decoder = SyncFrameDecoder()
        var frames: [SyncFrame] = []
        for chunk in stride(from: 0, to: stream.count, by: 17) {
            frames += try decoder.append(stream[chunk..<min(chunk + 17, stream.count)])
        }
        #expect(frames.map(\.kind) == [.message, .raw])
        #expect(frames[0].payload == Data("one".utf8))
        #expect(frames[1].payload.count == 300)
        var joined = SyncFrameDecoder()
        #expect(try joined.append(stream).count == 2)
    }

    @Test("an oversized or unknown frame is an error")
    func rejectsBadFrames() {
        var decoder = SyncFrameDecoder()
        let big = SyncFraming.header(kind: .message, length: SyncFraming.maximumMessageBytes + 1)
        #expect(throws: SyncFrameError.tooLarge) { try decoder.append(big) }
        var other = SyncFrameDecoder()
        #expect(throws: SyncFrameError.unknownKind) { try other.append(Data([0, 0, 0, 1, 9, 0])) }
    }
}

@Suite("Pairing code")
struct PairingCodeTests {
    @Test("both orders give the same six digits")
    func symmetric() {
        let a = Data((0..<32).map(UInt8.init))
        let b = Data((10..<42).map(UInt8.init))
        let code = PairingCode.code(a, b)
        #expect(code == PairingCode.code(b, a))
        #expect(code.count == PairingCode.digitCount)
        #expect(code.allSatisfy { $0.isNumber })
    }

    @Test("a different key gives a different code")
    func differs() {
        let a = Data(repeating: 1, count: 32)
        #expect(PairingCode.code(a, Data(repeating: 2, count: 32)) != PairingCode.code(a, Data(repeating: 3, count: 32)))
    }

    @Test("commitment matches only its own key")
    func commitment() {
        let key = Data(repeating: 9, count: 32)
        let commitment = PairingCode.commitment(of: key)
        #expect(PairingCode.isValid(commitment, for: key))
        #expect(!PairingCode.isValid(commitment, for: Data(repeating: 8, count: 32)))
    }

    @Test("both Macs derive the same shared key and it is 32 bytes")
    func sharedKey() throws {
        let first = Curve25519.KeyAgreement.PrivateKey()
        let second = Curve25519.KeyAgreement.PrivateKey()
        let one = try PairingCode.sharedKey(privateKey: first, peerPublicKey: second.publicKey.rawRepresentation)
        let two = try PairingCode.sharedKey(privateKey: second, peerPublicKey: first.publicKey.rawRepresentation)
        #expect(one == two)
        #expect(one.count == 32)
    }

    @Test("a malformed peer key throws")
    func badKey() {
        #expect(throws: (any Error).self) {
            try PairingCode.sharedKey(privateKey: Curve25519.KeyAgreement.PrivateKey(), peerPublicKey: Data([1, 2, 3]))
        }
    }
}

@Suite("Wallpaper sync policy and state")
struct WallpaperSyncTests {
    private func meta(_ stamp: Double, size: Int = 1000, kind: WallpaperKind = .desktop) -> WallpaperMeta {
        WallpaperMeta(kind: kind, timestamp: stamp, fileName: "a.jpg", size: size)
    }

    @Test("newest timestamp wins, equal does not")
    func newestWins() {
        #expect(WallpaperSyncPolicy.decision(for: meta(10), localTimestamp: nil) == .accept)
        #expect(WallpaperSyncPolicy.decision(for: meta(10), localTimestamp: 5) == .accept)
        #expect(WallpaperSyncPolicy.decision(for: meta(10), localTimestamp: 10) == .notNewer)
        #expect(WallpaperSyncPolicy.decision(for: meta(10), localTimestamp: 20) == .notNewer)
    }

    @Test("more than 20 MB is rejected, exactly 20 MB is fine")
    func sizeLimit() {
        #expect(WallpaperSyncPolicy.decision(for: meta(10, size: WallpaperSyncPolicy.maximumBytes), localTimestamp: nil) == .accept)
        #expect(WallpaperSyncPolicy.decision(for: meta(10, size: WallpaperSyncPolicy.maximumBytes + 1), localTimestamp: nil) == .tooLarge)
        #expect(WallpaperSyncPolicy.decision(for: meta(10, size: 0), localTimestamp: nil) == .invalid)
        #expect(WallpaperSyncPolicy.decision(for: meta(.nan), localTimestamp: nil) == .invalid)
    }

    @Test("a queued send is superseded by a newer wallpaper only")
    func superseded() {
        #expect(WallpaperSyncPolicy.isSuperseded(queued: 5, latest: 6))
        #expect(!WallpaperSyncPolicy.isSuperseded(queued: 5, latest: 5))
        #expect(!WallpaperSyncPolicy.isSuperseded(queued: 5, latest: nil))
    }

    @Test("the group converges: the older Mac pulls from the newer, never the reverse")
    func converges() {
        let older = WallpaperSyncState().recording(.desktop, at: 100)
        let newer = WallpaperSyncState().recording(.desktop, at: 200)
        #expect(older.decision(for: meta(200)) == .accept)
        #expect(newer.decision(for: meta(100)) == .notNewer)
        let afterPull = older.recording(.desktop, at: 200)
        #expect(afterPull.decision(for: meta(200)) == .notNewer)
    }

    @Test("state never moves backwards and keeps kinds apart")
    func monotonic() {
        let state = WallpaperSyncState().recording(.desktop, at: 50).recording(.desktop, at: 10)
        #expect(state.timestamp(of: .desktop) == 50)
        #expect(state.timestamp(of: .screenSaver) == nil)
        #expect(state.decision(for: meta(5, kind: .screenSaver)) == .accept)
    }
}

@Suite("Roaming")
struct RoamingTests {
    @Test("an object enters from the edge opposite the one it left through")
    func entryEdge() {
        let right = RoamingObject(id: "m", kind: .mascot, yFraction: 0.5, direction: .right, state: .walking)
        let left = RoamingObject(id: "m", kind: .mascot, yFraction: 0.5, direction: .left, state: .walking)
        #expect(right.direction.exitEdge == .right)
        #expect(right.entryEdge == .left)
        #expect(left.entryEdge == .right)
    }

    @Test("yFraction is clamped and a bad id is flagged")
    func clamps() {
        #expect(RoamingObject(id: "m", kind: .mascot, yFraction: 4, direction: .left, state: .walking).yFraction == 1)
        #expect(RoamingObject(id: "m", kind: .mascot, yFraction: .nan, direction: .left, state: .walking).yFraction == 1)
        #expect(!RoamingObject(id: "", kind: .mascot, yFraction: 0, direction: .left, state: .walking).hasValidID)
    }

    private func run(_ start: RoamingWalker, seconds: Double, canExit: @escaping (PeerSide) -> Bool)
        -> (RoamingWalker, RoamingObject?) {
        var walker = start
        for _ in 0..<Int(seconds * 20) {
            let (next, handoff) = walker.advanced(by: 0.05, maxX: 800, size: 64, canExit: canExit)
            walker = next
            if let handoff { return (walker, handoff) }
        }
        return (walker, nil)
    }

    @Test("with no neighbour it turns around and always stays on the screen")
    func staysInside() {
        var walker = RoamingWalker.spawn(id: "m", yFraction: 1, maxX: 800, seed: 3)
        for _ in 0..<(20 * 600) {
            walker = walker.advanced(by: 0.05, maxX: 800, size: 64, canExit: { _ in false }).walker
            #expect((0...800).contains(walker.x))
        }
    }

    @Test("with a neighbour it eventually walks off an edge and hands over its id")
    func handsOver() {
        let (_, handoff) = run(RoamingWalker.spawn(id: "m7", yFraction: 0.9, maxX: 800, seed: 5), seconds: 3600) { _ in true }
        #expect(handoff?.id == "m7")
        #expect(handoff?.yFraction == 0.9)
        #expect(handoff?.state == .walking)
    }

    @Test("only the side with a neighbour is used")
    func rightOnly() {
        let (_, handoff) = run(RoamingWalker.spawn(id: "m", yFraction: 1, maxX: 800, seed: 11), seconds: 3600) { $0 == .right }
        #expect(handoff?.direction == .right)
    }

    @Test("an arriving object walks in from its entry edge and then strolls")
    func arrives() {
        let object = RoamingObject(id: "m", kind: .mascot, yFraction: 0.5, direction: .right, state: .walking)
        var walker = RoamingWalker.arriving(object, maxX: 800, size: 64, seed: 1)
        #expect(walker.x == -64)
        #expect(walker.facesRight)
        #expect(walker.phase == .entering)
        for _ in 0..<40 { walker = walker.advanced(by: 0.05, maxX: 800, size: 64, canExit: { _ in true }).walker }
        #expect(walker.phase == .inside)
        #expect(walker.x > 0)
    }

    @Test("an arriving object does not bounce straight back out")
    func noImmediateReturn() {
        let object = RoamingObject(id: "m", kind: .mascot, yFraction: 0.5, direction: .left, state: .walking)
        let walker = RoamingWalker.arriving(object, maxX: 800, size: 64, seed: 1)
        #expect(walker.x == 864)
        #expect(!walker.facesRight)
        let (next, handoff) = walker.advanced(by: 0.05, maxX: 800, size: 64, canExit: { _ in true })
        #expect(handoff == nil)
        #expect(next.phase == .entering)
    }

    @Test("a resting handoff appears resting just inside the edge")
    func restingArrival() {
        let object = RoamingObject(id: "m", kind: .mascot, yFraction: 0.5, direction: .right, state: .resting)
        let walker = RoamingWalker.arriving(object, maxX: 800, size: 64, seed: 1)
        #expect(walker.x == 0)
        #expect(!walker.isWalking)
        #expect(walker.phase == .inside)
    }
}
