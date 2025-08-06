import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        resizeAllWindows()
        NSApplication.shared.terminate(self)
    }

    func resizeAllWindows() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

        for app in apps {
            if let pid = app.processIdentifier {
                if let appRef = AXUIElementCreateApplication(pid).takeRetainedValue() as? AXUIElement {
                    var windowRefs: CFArray?
                    let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowRefs)

                    if result == .success, let windows = windowRefs as? [AXUIElement] {
                        for windowRef in windows {
                            var position: CFTypeRef?
                            var size: CFTypeRef?

                            if AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute as CFString, &position) == .success,
                               let positionValue = position as? AXValue,
                               AXValueGetType(positionValue) == .cgPoint,
                               let point = AXValueGetValue(positionValue) as? CGPoint,

                               AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute as CFString, &size) == .success,
                               let sizeValue = size as? AXValue,
                               AXValueGetType(sizeValue) == .cgSize {

                                let newSize = CGSize(width: 700, height: 700)
                                let newSizeValue = AXValueCreate(AXValueType.cgSize, &newSize)

                                AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute as CFString, newSizeValue)

                            }
                        }
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
