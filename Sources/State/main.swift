import Cocoa
import Foundation
import ArgumentParser
import Logging
import StateCore

@main
struct Entry {
    static func main() {
        let level = (try? Config.load()).flatMap { Logger.Level(rawValue: $0.logLevel) }
        bootstrapLogging(level: level ?? .info)
        SpikotWM.main()
    }
}

struct SpikotWM: ParsableCommand {

    static let configuration = CommandConfiguration(
      abstract: "",
      version: spikotVersion,
      subcommands: [
        State.self,
        List.self,
        Focus.self,
        ConfigCommand.self,
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

        mutating func run() throws {
            let state = StateCore.State(config: try Config.load())
            state.initialize()
            state.flushCurrentState()
            state.printfStacks()
        }
    }

    struct List: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "List active windows")

        mutating func run() throws {
            let state = StateCore.State(config: try Config.load())
            state.initialize()
            print(state.listWindows())
        }
    }

    /// Prints the effective config: defaults, overlaid with the file, overlaid with the
    /// environment. Named ConfigCommand because `Config` is the StateCore type.
    struct ConfigCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
          commandName: "config",
          abstract: "Show the effective configuration and where it was read from")

        func run() throws {
            let path = Config.defaultPath
            let exists = FileManager.default.fileExists(atPath: path.path)
            print("# \(path.path) \(exists ? "" : "(not present, using defaults)")")
            print(try Config.load().prettyJSON())
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

        mutating func run() throws {
            let state = StateCore.State(config: try Config.load())
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
