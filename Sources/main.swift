import Cocoa
import Foundation

let config = Config(gap: 5,
                    activeMode: "twoColumns",
                    cachePath: ".spikot-wm-state.json",
                    useCache: false)

let state = State(config: config)
state.initialize()

let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        if arg == "up" || arg == "down" {
            state.rotateStack(direction: arg)
        } else {
            state.switchStack(toStack: arg)
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
