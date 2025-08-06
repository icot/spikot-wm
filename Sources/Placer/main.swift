
import Cocoa
import Foundation

import StateCore

let state = State(gap: 5,
                  activeMode: "twoColumns",
                  cachePath: ".spikot-wm-state.json",
                  useCache: true)

state.initialize()

let validArgs = ["0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        let targetStack = Int(arg)!
        let frontmostApp = NSWorkspace.shared.frontmostApplication!
        let pid = frontmostApp.processIdentifier
        if let activeWindow = state.visibleWindows.first(where: { $0.kCGWindowOwnerPID == pid }) {
            let screen = NSScreen.main!
            let frame = screen.frame
            let stackWidth = frame.width / CGFloat(state.activeMode.count)
            let newX = stackWidth * CGFloat(targetStack)
            let newBounds = CGRect(x: newX, y: frame.minY, width: stackWidth, height: frame.height)
            modifyWindow(windowNumber: CGWindowID(activeWindow.kCGWindowNumber), newBounds: newBounds)
            if let currentStack = state.stacks.firstIndex(where: { $0.contains(activeWindow) }) {
                state.stacks[currentStack].removeAll(where: { $0 == activeWindow })
                state.stacks[targetStack].insert(activeWindow, at: 0)
                state.flushCurrentState()
                print("Moved \(activeWindow.kCGWindowOwnerName) to stack \(targetStack)")
            }
        }
    } else {
        print("Argument must be one of \(validArgs)")
    }
} else {
    state.flushCurrentState()
    print("Missing argument: must supply one of \(validArgs)")
    print(state.sprintfStacks())
}

