import Foundation
import ObjCExceptionCatcher
import Testing

@Suite("SCTryObjC")
struct ObjCExceptionCatcherTests {
    @Test("runs the block and reports success")
    func success() {
        var didRun = false
        var error: NSError?
        #expect(SCTryObjC({ didRun = true }, &error))
        #expect(didRun && error == nil)
    }

    @Test("turns a raised NSException into an NSError instead of aborting")
    func catchesException() {
        var error: NSError?
        let didSucceed = SCTryObjC({
            NSException(name: .internalInconsistencyException, reason: "player started when engine not running").raise()
        }, &error)
        #expect(!didSucceed)
        #expect(error?.domain == NSExceptionName.internalInconsistencyException.rawValue)
        #expect(error?.localizedDescription == "player started when engine not running")
    }
}
