import AppKit
import CoreGraphics

/// Moves and resizes a window by its `CGWindowID`.
///
/// Kept so `spikot-placer` keeps working; spikot-win-80o.2 replaces it with
/// `spikot-wm place`. The body used to be 120 lines that found the element by comparing
/// bounds within 2 points, which could not separate two windows of one application with
/// near-identical frames. That matching now lives in `WindowIdentity.element(forWindowID:)`,
/// which tries the window id first and only falls back to geometry.
///
/// - Note: Requires Accessibility permission. Check `Accessibility.isTrusted` first.
public func modifyWindow(windowNumber: CGWindowID, newBounds: CGRect) {
    let windowIDArray = [windowNumber] as CFArray
    guard
        let info = CGWindowListCreateDescriptionFromArray(windowIDArray) as? [[String: Any]],
        let entry = info.first
    else {
        print("Error: Could not find window with ID \(windowNumber).")
        return
    }

    guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t else {
        print("Error: Could not get owner PID for window \(windowNumber).")
        return
    }

    let bounds: CGRect?
    if let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
        let xPos = boundsDict["X"], let yPos = boundsDict["Y"],
        let width = boundsDict["Width"], let height = boundsDict["Height"] {
        bounds = CGRect(x: xPos, y: yPos, width: width, height: height)
    } else {
        bounds = nil
    }

    guard
        let found = WindowIdentity.element(forWindowID: windowNumber, pid: pid, bounds: bounds)
    else {
        print("Warning: Could not find a matching window to modify for ID \(windowNumber).")
        return
    }

    if WindowIdentity.setFrame(newBounds, on: found.element) {
        print("Successfully modified window \(windowNumber).")
    } else {
        print("Error: Failed to set new bounds for window \(windowNumber).")
    }
}
