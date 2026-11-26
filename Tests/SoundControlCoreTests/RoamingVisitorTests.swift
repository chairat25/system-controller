import Foundation
import Testing
@testable import SoundControlCore

/// A visitor must look the way its home computer set it up — animal, colour and size — on every screen it walks
/// onto, including computers on an older version or a different platform.
@Suite("Roaming look across versions")
struct RoamingVisitorTests {
    private func json(_ object: RoamingObject) throws -> [String: Any] {
        let data = try JSONEncoder().encode(object)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ text: String) throws -> RoamingObject {
        try JSONDecoder().decode(RoamingObject.self, from: Data(text.utf8))
    }

    @Test("an animal older versions do not know is sent as the closest one they do, plus the exact species")
    func newAnimalHasLegacyLook() throws {
        let object = RoamingObject(id: "m", kind: .mascot, yFraction: 1, direction: .right, state: .walking,
                                   look: .tabby)
        let fields = try json(object)
        #expect(fields["look"] as? String == "cat")
        #expect(fields["species"] as? String == "tabby")
    }

    @Test("an animal every version knows is sent as itself")
    func knownAnimalIsUnchanged() throws {
        let fields = try json(RoamingObject(id: "m", kind: .mascot, yFraction: 1, direction: .right,
                                            state: .walking, look: .hippo))
        #expect(fields["look"] as? String == "hippo")
        #expect(fields["species"] as? String == "hippo")
    }

    @Test("the exact species wins over the legacy look")
    func speciesWins() throws {
        let object = try decode(#"{"id":"m","kind":"mascot","yFraction":1,"direction":"left","state":"walking","look":"cat","species":"tabby"}"#)
        #expect(object.look == .tabby)
    }

    @Test("a species from a newer version falls back to the legacy look, not to this computer's animal")
    func unknownSpeciesFallsBack() throws {
        let object = try decode(#"{"id":"m","kind":"mascot","yFraction":1,"direction":"left","state":"walking","look":"pig","species":"dragon"}"#)
        #expect(object.look == .pig)
    }

    @Test("a handoff from 1.6.0 without species still decodes")
    func oldHandoffDecodes() throws {
        let object = try decode(#"{"id":"m","kind":"mascot","yFraction":1,"direction":"left","state":"walking","look":"panda"}"#)
        #expect(object.look == .panda)
        #expect(object.hue == nil)
        #expect(object.scale == nil)
    }

    @Test("colour and size travel with the visitor and are kept in range")
    func styleTravels() throws {
        let object = RoamingObject(id: "m", kind: .mascot, yFraction: 1, direction: .right, state: .walking,
                                   look: .bunny, hue: 400, scale: 9)
        let decoded = try JSONDecoder().decode(RoamingObject.self, from: JSONEncoder().encode(object))
        #expect(decoded.hue == 40)
        #expect(decoded.scale == MascotStyle.scaleRange.upperBound)
        #expect(decoded.look == .bunny)
    }

    @Test("hello carries the version and platform, and an old hello without them still decodes")
    func helloVersion() throws {
        let hello = SyncMessage.hello(deviceID: "A", name: "PC", wantsWallpaper: false, wantsRoaming: true,
                                      appVersion: "1.7.0", platform: "windows")
        #expect(try SyncMessage.decode(hello.encoded()) == hello)
        let old = #"{"hello":{"deviceID":"A","name":"Mac","wantsWallpaper":true,"wantsRoaming":true}}"#
        #expect(try SyncMessage.decode(Data(old.utf8))
            == .hello(deviceID: "A", name: "Mac", wantsWallpaper: true, wantsRoaming: true, appVersion: nil, platform: nil))
    }

    @Test("a visitor that cannot be taken is returned")
    func returnRoundTrips() throws {
        let object = RoamingObject(id: "m", kind: .mascot, yFraction: 1, direction: .left, state: .walking, look: .pig)
        #expect(try SyncMessage.decode(SyncMessage.roamingReturn(object).encoded()) == .roamingReturn(object))
    }

    @Test("every animal maps to one that 1.6.0 can draw")
    func legacyIsAlwaysOld() {
        let known: Set<Mascot> = [.none, .cat, .pig, .puppy, .bunny, .panda, .penguin, .hippo]
        for mascot in Mascot.allCases { #expect(known.contains(mascot.legacy)) }
    }
}
