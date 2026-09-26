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
        guard let origin = axValue(element, kAXPositionAttribute, .cgPoint, CGPoint.zero),
            let size = axValue(element, kAXSizeAttribute, .cgSize, CGSize.zero)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Sets position and size, returning false if either write is refused.
    ///
    /// Position is written first: an application that clamps its size can otherwise end up
    /// somewhere unintended. The result is not re-read, so a window that refuses the
    /// requested size still reports success here.
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

        let positionResult = AXUIElementSetAttributeValue(
            element, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(
            element, kAXSizeAttribute as CFString, sizeValue)

        if positionResult != .success {
            logger.error("Setting position to \(rect.origin) failed: \(positionResult.rawValue)")
        }
        if sizeResult != .success {
            logger.error("Setting size to \(rect.size) failed: \(sizeResult.rawValue)")
        }
        return positionResult == .success && sizeResult == .success
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

    /// Reads an AXValue-wrapped attribute into a concrete type.
    private static func axValue<T>(
        _ element: AXUIElement,
        _ attribute: String,
        _ type: AXValueType,
        _ initial: T
    ) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
            let ref
        else { return nil }
        // AXUIElementCopyAttributeValue hands back a CFTypeRef; for position and size it is
        // always an AXValue, so the downcast cannot fail. The compiler rejects `as?` here
        // for exactly that reason.
        var out = initial
        guard AXValueGetValue(unsafeDowncast(ref, to: AXValue.self), type, &out) else {
            return nil
        }
        return out
    }
}
