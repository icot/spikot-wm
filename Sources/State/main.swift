import Cocoa
import Foundation
import StateCore

let validCommands = ["state", "list", "move", "focus", "window"]
let validArgs = [
  "state": [],
  "list": [],
  "move": ["left", "right", "up", "down", "0", "1", "2", "3", "4"],
  "focus": ["left", "right", "up", "down", "0", "1", "2", "3", "4"],
  "window": []
]

func exitWithHelp(errno: Int32, errmsg: String) {
    print("ERROR: \(errmsg)")
    print("")
    print("Usage: \(CommandLine.arguments[0]) <command> <argument>")
    print("")
    print("Valid Commands: \(validCommands)")
    print("")
    for command in validCommands {
        print(" *\(command)* valid arguments: \(validArgs[command]!)")
    }
    print("")
    exit(errno)
}

if CommandLine.arguments.count == 1 || CommandLine.arguments.count > 3 {
    exitWithHelp(errno: -1, errmsg: "Incorrect <command> or tooo many arguments")
}

let command = CommandLine.arguments[1]
let argCount = CommandLine.arguments.count

if validCommands.contains(command) {

    let arg = argCount == 3 ? CommandLine.arguments[2]: ""
    let argCond = (command == "state" || command == "list") ? argCount == 2 :
      ((command == "focus" || command == "move") ? validArgs[command]!.contains(arg) : true) 
     
    if argCond {
        // Initialize state
        let state = State(gap: 5,
                        activeMode: "twoColumns",
                        cachePath: ".spikot-wm-state.json",
                        useCache: true)
        state.initialize()
        // Execute command
        switch command {
        case "state":
            dump(state)
            let cachedState = state.loadCachedState()
            dump(cachedState)
            state.flushCurrentState()
        case "list":
            print(state.listWindows())
        case "focus":
            if arg == "up" || arg == "down" {
                state.rotateStack(direction: arg)
            } else {
                state.switchStack(toStack: arg)
            }
        case "window":
            state.focusWindow(windowNumber: arg)
        default:
            print("TODO: Not implemented")
        }
    } else {
        exitWithHelp(errno: -2, errmsg: "Unsupported argument: \(arg) for command: \(command)")
    }
} else {
    exitWithHelp(errno: -2, errmsg: "Unsupported command: \(command)")
}
