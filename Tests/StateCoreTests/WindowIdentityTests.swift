import ApplicationServices
import CoreGraphics
import Foundation
import SpikotAX
import Testing

@Suite("Window identity")
struct WindowIdentityTests {

    @Test("A derived id can never collide with a real window id")
    func derivedIDsAreOutOfRange() {
        // The window server allocates CGWindowIDs from the low range, so setting the top
        // bit keeps synthetic ids clear of real ones. Same rule as Rectangle's
        // deriveWindowId(fromElementHash:).
        let element = AXUIElementCreateSystemWide()
        let derived = WindowIdentity.derivedWindowID(for: element)
        #expect(derived & 0x8000_0000 == 0x8000_0000)
    }

    @Test("A derived id is stable for the same element")
    func derivedIDsAreStable() {
        let element = AXUIElementCreateApplication(1)
        #expect(
            WindowIdentity.derivedWindowID(for: element)
                == WindowIdentity.derivedWindowID(for: element))
    }

    @Test("identifier reports derived when the private symbol does not answer")
    func fallsBackToDerived() {
        // The system-wide element is not a window, so _AXUIElementGetWindow fails and the
        // fallback has to take over rather than returning nothing.
        let (id, source) = WindowIdentity.identifier(of: AXUIElementCreateSystemWide())
        #expect(source == .derived)
        #expect(id & 0x8000_0000 == 0x8000_0000)
    }

    @Test("exactWindowID returns nil for a non-window, rather than a made-up id")
    func exactReturnsNil() {
        #expect(WindowIdentity.exactWindowID(of: AXUIElementCreateSystemWide()) == nil)
    }

    @Test("Identical frames match, which is why geometry alone cannot separate windows")
    func identicalFramesMatch() {
        // This is the ambiguity the private symbol removes: two windows of one application
        // with the same frame are indistinguishable to the geometry fallback.
        let frame = CGRect(x: 10, y: 40, width: 1131, height: 1390)
        #expect(WindowIdentity.matches(frame, frame))
    }

    @Test("Frames within the tolerance match and frames outside it do not")
    func toleranceBoundary() {
        let base = CGRect(x: 100, y: 100, width: 800, height: 600)
        let tolerance = WindowIdentity.geometryTolerance

        let justInside = base.offsetBy(dx: tolerance - 0.5, dy: 0)
        let justOutside = base.offsetBy(dx: tolerance, dy: 0)
        #expect(WindowIdentity.matches(base, justInside))
        #expect(!WindowIdentity.matches(base, justOutside), "the comparison is strictly <")
    }

    @Test("Each of the four components is compared")
    func allComponentsCompared() {
        let base = CGRect(x: 0, y: 0, width: 100, height: 100)
        let shift = WindowIdentity.geometryTolerance + 1
        #expect(!WindowIdentity.matches(base, base.offsetBy(dx: shift, dy: 0)))
        #expect(!WindowIdentity.matches(base, base.offsetBy(dx: 0, dy: shift)))
        #expect(
            !WindowIdentity.matches(
                base, CGRect(x: 0, y: 0, width: 100 + shift, height: 100)))
        #expect(
            !WindowIdentity.matches(
                base, CGRect(x: 0, y: 0, width: 100, height: 100 + shift)))
    }

    @Test("A process with no accessibility windows yields nil")
    func noWindowElements() {
        // launchd owns none.
        #expect(WindowIdentity.windowElements(ofPID: 1) == nil)
    }

    @Test("Looking up a window id in a process that has none fails without the fallback")
    func lookupFailsCleanly() {
        #expect(WindowIdentity.element(forWindowID: 12345, pid: 1) == nil)
        #expect(
            WindowIdentity.element(
                forWindowID: 12345, pid: 1,
                bounds: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }
}
