import Cocoa
import Foundation

import State

let state = State(gap: 5,
                  activeMode: "twoColumns",
                  cachePath: ".spikot-wm-state.json",
                  useCache: true)

state.initialize()

let validArgs = ["0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        // TODO Send active window to desired stack
        print("Sending active windows to stack \(arg)")
    } else {
        print("Argument must be one of \(validArgs)")
    }
} else {
    state.flushCurrentState()
    print("Missing argument: must supply one of \(validArgs)")
    print(state.sprintfStacks())
}
