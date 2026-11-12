import Foundation
import Testing
@testable import SoundControlCore

@Suite("Keyboard lock")
struct KeyboardLockTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test("counts down from the safety limit")
    func countsDown() {
        let lock = KeyboardLock(lockedAt: start)
        #expect(lock.remaining(at: start) == KeyboardLock.maxDuration)
        #expect(lock.remaining(at: start.addingTimeInterval(60)) == KeyboardLock.maxDuration - 60)
        #expect(!lock.hasExpired(at: start.addingTimeInterval(60)))
    }

    @Test("unlocks by itself once the safety limit passes")
    func expires() {
        let lock = KeyboardLock(lockedAt: start)
        let later = start.addingTimeInterval(KeyboardLock.maxDuration + 5)
        #expect(lock.remaining(at: later) == 0)
        #expect(lock.hasExpired(at: later))
    }

    @Test("owner lock never unlocks by itself, only the owner can open it")
    func ownerLockDoesNotExpire() {
        let lock = KeyboardLock(lockedAt: start, unlock: .ownerAuthentication)
        let later = start.addingTimeInterval(KeyboardLock.maxDuration * 10)
        #expect(!lock.expires)
        #expect(!lock.hasExpired(at: later))
    }

    @Test("hold lock expires by default")
    func holdLockExpiresByDefault() {
        let lock = KeyboardLock(lockedAt: start)
        #expect(lock.unlock == .holdButton)
        #expect(lock.expires)
    }

    @Test("keyboard sounds are silenced while locked, mouse sounds are not")
    func silencesKeyboardTriggers() {
        for trigger in [TriggerID.keyTyped, .returnKey, .deleteKey, .spaceKey, .capsLockOn, .capsLockOff] {
            #expect(KeyboardLock.silences(trigger))
        }
        for trigger in [TriggerID.mouseClick, .rightClick, .chargerConnected] {
            #expect(!KeyboardLock.silences(trigger))
        }
    }
}
