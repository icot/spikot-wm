import Cocoa
import Foundation
import ArgumentParser
import StateCore

@main
struct Entry {
    static func main() {
        bootstrapLogging()
        SpikotWM.main()
    }
}

struct SpikotWM: ParsableCommand {

    static let configuration = CommandConfiguration(
      abstract: "",
      version: "0.0.1",
      subcommands: [
        State.self,
        List.self,
        Focus.self,
      ],
      defaultSubcommand: State.self)

}

struct TargetOptions: ParsableArguments {

    @Flag(
      name: [.customLong("window"), .customShort("w")],
      help: "Refer to a window ID")
    var window: Bool = false

    @Argument(help: "Target identifier")
    var target: String

}

extension SpikotWM {

    struct State: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "Display window state")

        mutating func run() {
            let state = StateCore.State(gap: 5,
                        activeMode: "twoColumns",
                        cachePath: ".spikot-wm-state.json",
                        useCache: true)
            state.initialize()
            state.flushCurrentState()
            state.printfStacks()
        }
    }

    struct List: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "List active windows")

        mutating func run() {
            let state = StateCore.State(gap: 5,
                        activeMode: "twoColumns",
                        cachePath: ".spikot-wm-state.json",
                        useCache: true)
            state.initialize()
            print(state.listWindows())
        }
    }

    struct Focus: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "Switch focus to a direction or window")

        @OptionGroup var options: TargetOptions

        func validate() throws {
            if options.window {
                guard Int32(options.target) != nil else {
                    throw ValidationError("Window ID must be a valid Integer")
                    }
            } else {
                let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]
                if !validArgs.contains(options.target) {
                    throw ValidationError("Argument must be one of \(validArgs).")
                }
            }
        }

        mutating func run() {
            let state = StateCore.State(gap: 5,
                        activeMode: "twoColumns",
                        cachePath: ".spikot-wm-state.json",
                        useCache: true)
            state.initialize()
            if options.window {
                state.focusWindow(windowNumber: options.target)
            } else {
                if options.target == "up" || options.target == "down" {
                    state.rotateStack(direction: options.target)
                } else {
                    state.switchStack(toStack: options.target)
                }
            }
        }
    }
}
