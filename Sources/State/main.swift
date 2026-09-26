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
        Doctor.self,
        Debug.self,
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

    /// Reports whether the pieces spikot-wm depends on are in place.
    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Check permissions, configuration and display state")

        @Flag(
          name: [.customLong("request-permission")],
          help: "Show the system Accessibility dialog if permission is missing")
        var requestPermission: Bool = false

        func run() throws {
            if requestPermission && !Accessibility.isTrusted {
                Accessibility.requestTrust()
            }

            // Load without throwing, so a broken config is reported as a failing check
            // rather than aborting the whole diagnostic.
            var config: Config?
            var configError: Error?
            do { config = try Config.load() } catch { configError = error }

            let checks = Diagnostics.run(
                config: config,
                configError: configError,
                configPath: Config.defaultPath.path)
            print(Diagnostics.format(checks))

            if !Diagnostics.allPassed(checks) {
                throw ExitCode(1)
            }
        }
    }

    /// Diagnostics for the Accessibility layer, not part of the everyday surface.
    struct Debug: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Inspect how windows map to Accessibility elements",
          subcommands: [AxCommand.self])
    }

    /// Shows, per window, whether its Accessibility element was found by window id or
    /// only by geometry, and whether the two frames agree.
    ///
    /// Declared beside Debug rather than inside it: the lint limit is one level of
    /// nesting, and this is already inside an extension of SpikotWM.
    struct AxCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
          commandName: "ax",
          abstract: "Map every visible window to its Accessibility element")

        func run() throws {
            guard Accessibility.isTrusted else {
                throw ValidationError(
                    "Accessibility permission is required.\n\(Accessibility.grantInstructions)")
            }

            let state = StateCore.State(config: try Config.load())
            state.initialize()

            print(
                "windowID  pid     owner                 source    "
                    + "cg-bounds                  ax-frame                   agree")
            for window in state.visibleWindows {
                print(Self.row(for: window))
            }
        }

        private static func row(for window: Window) -> String {
            let cgBounds = window.kCGWindowBounds.rect
            let found = WindowIdentity.element(
                forWindowID: CGWindowID(window.kCGWindowNumber),
                pid: window.kCGWindowOwnerPID,
                bounds: cgBounds)

            let axFrame = found.flatMap { WindowIdentity.frame(of: $0.element) }
            let agree = axFrame.map { WindowIdentity.matches($0, cgBounds) ? "yes" : "NO" } ?? "-"

            return [
                pad(String(window.kCGWindowNumber), 9),
                pad(String(window.kCGWindowOwnerPID), 7),
                pad(window.kCGWindowOwnerName, 21),
                pad(found?.source.rawValue ?? "none", 9),
                pad(describe(cgBounds), 26),
                pad(axFrame.map(describe) ?? "-", 26),
                agree,
            ].joined(separator: " ")
        }

        private static func describe(_ rect: CGRect) -> String {
            "\(Int(rect.width))x\(Int(rect.height))@(\(Int(rect.minX)),\(Int(rect.minY)))"
        }

        private static func pad(_ text: String, _ width: Int) -> String {
            text.count >= width
                ? String(text.prefix(width))
                : text.padding(toLength: width, withPad: " ", startingAt: 0)
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
                    try state.rotateStack(direction: options.target)
                } else {
                    try state.switchStack(toStack: options.target)
                }
            }
        }
    }
}
