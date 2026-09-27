import AppKit
import ApplicationServices
import CSpikotAX
import CoreGraphics
import Foundation
import Logging

let logger = Logger(label: "org.traf.spikot-wm.ax")

/// How a window id was obtained, so callers and `spikot-wm debug ax` can tell a reliable
/// answer from a guess.
public enum WindowIDSource: String, Sendable {
    /// `_AXUIElementGetWindow`. Exact.
    case privateAPI = "private"
    /// Position and size compared against CGWindowList bounds within a tolerance. Cannot
    /// separate two windows of one application that have near-identical frames.
    case geometry
    /// Synthesised from the element's hash. Stable for one element within one process
    /// lifetime, and never equal to a real window id, so it is usable as a dictionary key
    /// but not for talking to CGWindowList.
    case derived
}

/// Reading and writing window geometry through the Accessibility API, and mapping between
/// `AXUIElement` and `CGWindowID`.
public enum WindowIdentity {

    /// How far apart two frames may be and still count as the same window, in points.
    ///
    /// Only used by the geometry fallback. The window server and the Accessibility API can
    /// report a frame a pixel or two apart, and a window with a shadow or a border overlay
    /// differs by more: the JankyBorders overlay this project filters out sits 16 points
    /// outside the window it draws around.
    public static let geometryTolerance: CGFloat = 2

    /// The exact window id for an element, or nil when the private symbol does not answer.
    ///
    /// Returns nil rather than falling back, so a caller that needs certainty can tell.
    /// `identifier(of:)` applies the fallback.
    public static func exactWindowID(of element: AXUIElement) -> CGWindowID? {
        var identifier: UInt32 = 0
        guard _AXUIElementGetWindow(element, &identifier) == .success, identifier != 0 else {
            return nil
        }
        return CGWindowID(identifier)
    }

    /// A usable identifier for an element, saying where it came from.
    ///
    /// Falls back to a synthetic id so per-window bookkeeping keeps working if the private
    /// symbol ever stops answering. A `.derived` id must never be handed to CGWindowList.
    public static func identifier(of element: AXUIElement) -> (id: CGWindowID, source: WindowIDSource) {
        if let exact = exactWindowID(of: element) {
            return (exact, .privateAPI)
        }
        return (derivedWindowID(for: element), .derived)
    }

    /// An id synthesised from the element's hash.
    ///
    /// The top bit is set so the value cannot collide with a real `CGWindowID`, which the
    /// window server allocates from the low range. Same approach as Rectangle's
    /// `AccessibilityElement.deriveWindowId(fromElementHash:)`.
    public static func derivedWindowID(for element: AXUIElement) -> CGWindowID {
        CGWindowID(0x8000_0000) | (CGWindowID(truncatingIfNeeded: CFHash(element)) & 0x7FFF_FFFF)
    }

    /// The window elements an application exposes, or nil when it exposes none.
    public static func windowElements(ofPID pid: pid_t) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else {
            logger.debug("No window elements for pid \(pid)")
            return nil
        }
        return windows
    }

    /// Finds the element for a window id.
    ///
    /// Matches on the window id first. `bounds` enables the geometry fallback, and should
    /// be the window's CGWindowList bounds; without it, a failure to match by id is a
    /// failure outright.
    public static func element(
        forWindowID windowID: CGWindowID,
        pid: pid_t,
        bounds: CGRect? = nil
    ) -> (element: AXUIElement, source: WindowIDSource)? {
        guard let windows = windowElements(ofPID: pid) else { return nil }

        for element in windows where exactWindowID(of: element) == windowID {
            return (element, .privateAPI)
        }

        guard let bounds else {
            logger.debug("Window \(windowID) not found among \(windows.count) elements of pid \(pid)")
            return nil
        }
        for element in windows {
            guard let elementFrame = frame(of: element) else { continue }
            if matches(elementFrame, bounds) {
                logger.debug("Window \(windowID) matched by geometry, not by id")
                return (element, .geometry)
            }
        }
        logger.debug("Window \(windowID) matched neither by id nor geometry for pid \(pid)")
        return nil
    }

    /// True when two frames agree within `geometryTolerance` on all four components.
    public static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < geometryTolerance
            && abs(lhs.origin.y - rhs.origin.y) < geometryTolerance
            && abs(lhs.size.width - rhs.size.width) < geometryTolerance
            && abs(lhs.size.height - rhs.size.height) < geometryTolerance
    }

    /// The element's position and size, in Accessibility coordinates: top-left origin,
    /// y increasing downwards. `NSScreen.frame` uses the opposite y direction, so the two
    /// must be converted before being compared. See spikot-win-80o.1.
    public static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute),
            let extent = size(element, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// Sets a window's frame, writing **size, position, size**.
    ///
    /// Three writes, which is what Rectangle does (`AccessibilityElement.setFrame`, size then
    /// position then size again). One pass of position-then-size is not enough, and this was
    /// measured rather than assumed: Firefox sitting at `1137x1390@(1151,40)` and asked for
    /// `1705x1390@(10,40)` took the new size and stayed at x=1151. Running the same placement a
    /// second time moved it. The first size write is what makes room for the move, and the last
    /// one undoes any clamping the application applied while it was still at its old position.
    ///
    /// Returns false when a write is refused. It does not check where the window actually ended
    /// up: an application that quantises its size, as Emacs and Ghostty do to character cells,
    /// legitimately lands a few points off, so the caller reads the frame back if it cares.
    @discardableResult
    public static func setFrame(_ rect: CGRect, on element: AXUIElement) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            logger.error("Could not build AXValues for \(rect)")
            return false
        }

        func write(_ attribute: String, _ value: AXValue) -> AXError {
            AXUIElementSetAttributeValue(element, attribute as CFString, value)
        }

        let firstSize = write(kAXSizeAttribute, sizeValue)
        let position = write(kAXPositionAttribute, positionValue)
        let finalSize = write(kAXSizeAttribute, sizeValue)

        if position != .success {
            logger.error("Setting position to \(rect.origin) failed: \(position.rawValue)")
        }
        if finalSize != .success {
            logger.error("Setting size to \(rect.size) failed: \(finalSize.rawValue)")
        }
        // The first write is allowed to fail on its own: some applications refuse a size that
        // does not fit where the window currently is, which is exactly what the move fixes.
        if firstSize != .success && finalSize == .success {
            logger.debug("First size write was refused; the pass after the move took it")
        }
        return position == .success && finalSize == .success
    }

    /// The window's title, from `kAXTitle`.
    ///
    /// Needs only Accessibility permission, unlike `kCGWindowName` from CGWindowList,
    /// which needs Screen Recording for other applications' windows.
    public static func title(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
            == .success
        else { return nil }
        return value as? String
    }

    /// Reads a `kAXPosition`-style attribute.
    ///
    /// Concrete rather than generic over the output type: taking `&out` on a generic `T`
    /// makes a raw pointer to something that might hold an object reference, which the
    /// compiler rightly warns about. Only CGPoint and CGSize are ever needed.
    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var out = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &out) else { return nil }
        return out
    }

    /// Reads a `kAXSize`-style attribute.
    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var out = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &out) else { return nil }
        return out
    }

    /// The raw AXValue for an attribute.
    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
            let ref
        else { return nil }
        // For position and size the result is always an AXValue, which is why the compiler
        // rejects a conditional downcast here.
        return unsafeDowncast(ref, to: AXValue.self)
    }
}

extension WindowIdentity {

    /// Brings one specific window to the front of its application and focuses it.
    ///
    /// Three steps, because no single one is enough. `kAXMain` marks which of the
    /// application's windows is the main one, `kAXRaiseAction` brings it above its
    /// siblings, and activating the application brings that application above the others.
    /// Setting only `kAXMain` leaves the window behind its siblings; activating only the
    /// application lets macOS pick which of its windows comes up, which is the
    /// multiple-windows-per-application problem.
    ///
    /// Returns false when the raise is refused. Some applications ignore `kAXMain` while
    /// still honouring the raise, so a false does not always mean nothing happened.
    @discardableResult
    public static func raise(_ element: AXUIElement, pid: pid_t) -> Bool {
        let mainResult = AXUIElementSetAttributeValue(
            element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if mainResult != .success {
            logger.debug("Setting kAXMain failed: \(mainResult.rawValue)")
        }

        let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if raiseResult != .success {
            logger.debug("kAXRaiseAction failed: \(raiseResult.rawValue)")
        }

        NSRunningApplication(processIdentifier: pid)?.activate()
        return raiseResult == .success
    }

    /// Resolves a window id and raises it in one step.
    ///
    /// `bounds` enables the geometry fallback when the window id cannot be matched.
    @discardableResult
    public static func raiseWindow(
        id windowID: CGWindowID,
        pid: pid_t,
        bounds: CGRect? = nil
    ) -> Bool {
        guard let found = element(forWindowID: windowID, pid: pid, bounds: bounds) else {
            logger.debug("Cannot raise window \(windowID): no element for pid \(pid)")
            return false
        }
        return raise(found.element, pid: pid)
    }
}
