/*

 Window related helper methods

 */

import Cocoa
import ApplicationServices

func stack(windows: [Window], mode: [Int]) -> [[Window]]? {
    var stacks: [[Window]] = []
    for stackID in mode.indices {
        let windowsInStack = windows.filter({ windowInColumn(window: $0, mode: mode) == stackID })
        stacks.append(windowsInStack)
    }
    return stacks
}

func windowInColumn(window: Window, mode: [Int]) -> Int? {
    let coordX1 = window.kCGWindowBounds.coordX
    let coordX2 = coordX1 + window.kCGWindowBounds.width
    for (position, stackCenter) in mode.enumerated() {
        if (stackCenter >  coordX1) && (stackCenter <= coordX2) {
            // This check assumes windows are properly stacked
            return position
        }
    }
    return nil
}

extension NSRunningApplication {
    func set(_ attributes: [String: Any]) throws {
        let appRef = AXUIElementCreateApplication(processIdentifier)

        for (attribute, value) in attributes {
            var ref: CFTypeRef?

            switch value {
            case var point as CGPoint:
                ref = AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!, &point)
            case var size as CGSize:
                ref = AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!, &size)
            default:
                print("Unsupported attribute type")
                continue
            }

            if let ref = ref {
                let error = AXUIElementSetAttributeValue(appRef, attribute as CFString, ref)
                guard error == .success else {
                    throw NSError(
                        domain: "AXError",
                        code: Int(error.rawValue),
                        userInfo: [
                            NSLocalizedDescriptionKey: "Failed to set attribute \(attribute)"
                        ])
                }
            }
        }
    }
}

// https://developer.apple.com/documentation/appkit/nswindow/setframetopleftpoint(_:)

/*

 setFrameTopLeftPoint(NSPoint)


NSWindow.setFrame(_ frameRect: NSRect, display flag: Bool)
NSWindow.setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool)

let newFrame = CGRect(x: 100, y: 100, width: 600, height: 400)
window.setFrame(newFrame, display: true)

Ghostty + Borders on stack 0, full screen (aka single stack)

        ▿ StateTool.Window
          - kCGWindowAlpha: 1
          ▿ kCGWindowBounds: StateTool.WindowBounds
            - height: 930
            - width: 1498
            - coordX: -1505
            - coordY: 434
          - kCGWindowIsOnscreen: 1
          - kCGWindowLayer: 0
          - kCGWindowMemoryUsage: 2288
          - kCGWindowNumber: 12774
          - kCGWindowOwnerName: "Ghostty"
          - kCGWindowOwnerPID: 69462
          - kCGWindowSharingState: 0
          - kCGWindowStoreType: 1
        ▿ StateTool.Window
          - kCGWindowAlpha: 1
          ▿ kCGWindowBounds: StateTool.WindowBounds
            - height: 962
            - width: 1530
            - coordX: -1521
            - coordY: 418
          - kCGWindowIsOnscreen: 1
          - kCGWindowLayer: 0
          - kCGWindowMemoryUsage: 5917024
          - kCGWindowNumber: 12777
          - kCGWindowOwnerName: "borders"
          - kCGWindowOwnerPID: 26696
          - kCGWindowSharingState: 0
          - kCGWindowStoreType: 2

Firefox plus borders on stack 3 (slightly resized towards stack 1)

      ▿ 2 elements
        ▿ StateTool.Window
          - kCGWindowAlpha: 1
          ▿ kCGWindowBounds: StateTool.WindowBounds
            - height: 1400
            - width: 1355
            - coordX: 7
            - coordY: 32
          - kCGWindowIsOnscreen: 1
          - kCGWindowLayer: 0
          - kCGWindowMemoryUsage: 2288
          - kCGWindowNumber: 6993
          - kCGWindowOwnerName: "Firefox"
          - kCGWindowOwnerPID: 1205
          - kCGWindowSharingState: 0
          - kCGWindowStoreType: 1
        ▿ StateTool.Window
          - kCGWindowAlpha: 1
          ▿ kCGWindowBounds: StateTool.WindowBounds
            - height: 1432
            - width: 1387
            - coordX: -9
            - coordY: 16
          - kCGWindowIsOnscreen: 1
          - kCGWindowLayer: 0
          - kCGWindowMemoryUsage: 8079712
          - kCGWindowNumber: 11474
          - kCGWindowOwnerName: "borders"
          - kCGWindowOwnerPID: 26696
          - kCGWindowSharingState: 0
          - kCGWindowStoreType: 2


 */
