import Testing
@testable import SoundControlCore

@Suite("Owner unlock path")
struct OwnerUnlockPathTests {
    @Test("Touch ID is checked inline in the overlay when the Mac has it")
    func touchIDStaysInline() {
        let path = OwnerUnlockPath(hasBiometry: true)
        #expect(path == .inlineTouchID)
    }

    @Test("without Touch ID the system password prompt is used instead")
    func missingTouchIDUsesSystemPrompt() {
        let path = OwnerUnlockPath(hasBiometry: false)
        #expect(path == .systemPrompt)
    }
}
