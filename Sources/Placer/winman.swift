import CoreGraphics
import AppKit

private func getWindowInfo(for windowNumber: CGWindowID) -> [String: Any]? {
    let windowIDArray = [windowNumber] as CFArray
    guard let windowInfoList = CGWindowListCreateDescriptionFromArray(windowIDArray) as? [[String: Any]] else {
        return nil
    }
    return windowInfoList.first
}

private func getCurrentBounds(from windowInfo: [String: Any]) -> CGRect? {
    guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
          let xPos = boundsDict["X"],
          let yPos = boundsDict["Y"],
          let width = boundsDict["Width"],
          let height = boundsDict["Height"] else {
        return nil
    }
    return CGRect(x: xPos, y: yPos, width: width, height: height)
}

private func findAndModifyWindow(
    in windowList: [AXUIElement],
    matching currentBounds: CGRect,
    with newBounds: CGRect,
    windowNumber: CGWindowID
) {
    for windowElement in windowList {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            windowElement, kAXPositionAttribute as CFString, &positionRef
        ) == .success,
              AXUIElementCopyAttributeValue(
                windowElement, kAXSizeAttribute as CFString, &sizeRef
              ) == .success else {
            continue
        }

        if let positionRef, let sizeRef {
            // AXUIElementCopyAttributeValue hands back a CFTypeRef; for the position and
            // size attributes it is always an AXValue, so the downcast cannot fail (the
            // compiler rejects `as?` here for exactly that reason).
            let positionValue = unsafeDowncast(positionRef, to: AXValue.self)
            let sizeValue = unsafeDowncast(sizeRef, to: AXValue.self)
            var windowPos: CGPoint = .zero
            var windowSize: CGSize = .zero
            AXValueGetValue(positionValue, .cgPoint, &windowPos)
            AXValueGetValue(sizeValue, .cgSize, &windowSize)

            if abs(windowPos.x - currentBounds.origin.x) < 2 &&
               abs(windowPos.y - currentBounds.origin.y) < 2 &&
               abs(windowSize.width - currentBounds.size.width) < 2 &&
               abs(windowSize.height - currentBounds.size.height) < 2 {
                var newOrigin = newBounds.origin
                var newSize = newBounds.size

                guard let newPositionValue = AXValueCreate(.cgPoint, &newOrigin),
                      let newSizeValue = AXValueCreate(.cgSize, &newSize) else {
                    print("Error: Could not create AXValue for new bounds.")
                    continue
                }

                let positionSuccess = AXUIElementSetAttributeValue(
                    windowElement, kAXPositionAttribute as CFString, newPositionValue
                ) == .success
                let sizeSuccess = AXUIElementSetAttributeValue(
                    windowElement, kAXSizeAttribute as CFString, newSizeValue
                ) == .success

                if positionSuccess && sizeSuccess {
                    print("Successfully modified window \(windowNumber).")
                    return
                } else {
                    print("Error: Failed to set new bounds for window \(windowNumber).")
                }
            }
        }
    }
    print("Warning: Could not find a matching window to modify for ID \(windowNumber).")
}

/**
 Modifies the position and size of an application window.

 - Note: The application running this code must be granted Accessibility permissions
         in System Settings > Privacy & Security > Accessibility.

 - Parameter windowNumber: The unique identifier for the window (kCGWindowNumber).
 - Parameter newBounds: A CGRect defining the new position and size for the window.
*/
public func modifyWindow(windowNumber: CGWindowID, newBounds: CGRect) {
    guard let windowInfo = getWindowInfo(for: windowNumber) else {
        print("Error: Could not find window with ID \(windowNumber).")
        return
    }

    guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
        print("Error: Could not get owner PID for window \(windowNumber).")
        return
    }

    guard let currentBounds = getCurrentBounds(from: windowInfo) else {
        print("Error: Could not get bounds for window \(windowNumber).")
        return
    }

    let appElement = AXUIElementCreateApplication(pid)
    var windows: AnyObject?
    guard AXUIElementCopyAttributeValue(
        appElement, kAXWindowsAttribute as CFString, &windows
    ) == .success,
          let windowList = windows as? [AXUIElement] else {
        print("Error: Could not get windows for application with PID \(pid).")
        return
    }

    findAndModifyWindow(
        in: windowList,
        matching: currentBounds,
        with: newBounds,
        windowNumber: windowNumber
    )
}
