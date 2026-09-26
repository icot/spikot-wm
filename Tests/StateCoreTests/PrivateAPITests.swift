import ApplicationServices
import CSpikotAX
import Foundation
import Testing

@testable import StateCore

@Suite("Private AX symbol")
struct PrivateAPITests {

    /// `_AXUIElementGetWindow` is exported by ApplicationServices but declared in no
    /// public header. If Apple removes it, the link fails and this target stops building,
    /// which is the loud failure this test exists to guarantee. Calling it here also
    /// proves the CSpikotAX declaration matches the real symbol: a wrong signature would
    /// crash or return nonsense rather than a clean error.
    @Test("The symbol links and rejects a non-window element")
    func rejectsNonWindowElement() {
        // The system-wide element is a valid AXUIElement but not a window, so the call
        // must fail rather than fill in an identifier.
        let systemWide = AXUIElementCreateSystemWide()
        var identifier: UInt32 = 0xDEAD_BEEF
        let result = _AXUIElementGetWindow(systemWide, &identifier)

        #expect(result != .success, "the system-wide element is not a window")
        #expect(identifier == 0xDEAD_BEEF, "a failed call must leave the identifier alone")
    }

    /// Guards the assumption the geometry fallback is built on. If an application element
    /// ever started returning a window id, the fallback ordering in spikot-win-6sd.2 would
    /// need revisiting.
    @Test("An application element is not treated as a window either")
    func rejectsApplicationElement() {
        // PID 1 is launchd, which owns no accessibility windows.
        let app = AXUIElementCreateApplication(1)
        var identifier: UInt32 = 0
        #expect(_AXUIElementGetWindow(app, &identifier) != .success)
    }
}
