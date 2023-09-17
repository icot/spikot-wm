import Cocoa
import Foundation

let config = Config(gap: 5,
                    activeMode: "twoColumns",
                    cachePath: ".spikot-wm-state.json",
                    useCache: false)

let state = State(config: config)
state.initialize()

// Main
let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        // TODO Implement currentStack as State method, maybe internal 
        let frontAppPid = NSWorkspace.shared.frontmostApplication!.processIdentifier
        let frontWin: Window? = state.visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontAppPid })
        let currentStack = windowInColumn(window: frontWin!, mode: state.activeMode) ?? -1

        if arg == "up" || arg == "down" {
            self.rotateStack(currentStack: currentStack, direction: arg)
        } else {
            self.switchStack(currentStack: currentStack, toStack: arg)
        }
    } else {
        print("Argument must be one of \(validArgs)")
    }
} else {
    dump(state)
    let cachedState = state.loadCachedState()
    dump(cachedState)
    state.flushCurrentState()
}
