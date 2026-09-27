import Cocoa
import Dispatch
import Foundation
import ArgumentParser
import Logging
import StateCore

// ListFormat lives in StateCore, which does not and should not depend on ArgumentParser.
extension ListFormat: ExpressibleByArgument {}

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
        Place.self,
        ConfigCommand.self,
        Doctor.self,
        Debug.self,
      ],
      defaultSubcommand: State.self)

}

struct TargetOptions: ParsableArguments {

    @Flag(
      name: [.customLong("window"), .customShort("w")],
      help: "Treat the target as a window number, falling back to a pid")
    var window: Bool = false

    @Flag(
      name: [.customLong("pid")],
      help: "Treat the target as a process id and activate that application")
    var pid: Bool = false

    @Argument(help: "Target identifier")
    var target: String

}

/// Shared by the commands that can be served by the agent.
struct DaemonOptions: ParsableArguments {
    @Flag(
      name: [.customLong("no-daemon")],
      help: "Run in this process even when the agent is available")
    var noDaemon = false

    @Flag(name: [.customLong("explain")], help: "Report which path served the command")
    var explain = false
}

extension SpikotWM {

    struct State: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "Display window state")

        @OptionGroup var daemon: DaemonOptions

        mutating func run() throws {
            let route = try Client.run(Request(cmd: "state"), noDaemon: daemon.noDaemon) {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                state.flushCurrentState()
                return state.stacksReport()
            }
            if daemon.explain { FileHandle.standardError.write(Data("served by: \(route.rawValue)\n".utf8)) }
        }
    }

    struct List: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "List active windows")

        @Option(
          name: [.customLong("format"), .customShort("f")],
          help: "Output format: \(ListFormat.allCases.map(\.rawValue).joined(separator: ", "))")
        var format: ListFormat = .legacy

        @OptionGroup var daemon: DaemonOptions

        mutating func run() throws {
            let route = try Client.run(
                Request(cmd: "list", args: ["format": format.rawValue]),
                noDaemon: daemon.noDaemon
            ) {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                return try state.listWindows(format: format)
            }
            if daemon.explain { FileHandle.standardError.write(Data("served by: \(route.rawValue)\n".utf8)) }
        }
    }

    /// Moves a window.
    ///
    /// A bare number is a stack index, so `place 1` does what `spikot-placer 1` did, with the
    /// index checked instead of trapping and with the window named rather than guessed.
    struct Place: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Move a window to a stack")

        @Argument(help: "What to do: \(PlacementAction.names.joined(separator: ", "))")
        var action: String

        @Option(
          name: [.customLong("window"), .customShort("w")],
          help: "Window number from `spikot-wm list`; defaults to the frontmost application's")
        var window: Int?

        @OptionGroup var daemon: DaemonOptions

        mutating func run() throws {
            var args = ["action": action]
            if let window { args["window"] = String(window) }
            let subject = window
            let wanted = action
            let route = try Client.run(
                Request(cmd: "place", args: args), noDaemon: daemon.noDaemon
            ) {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                let parsed = try PlacementAction.parse(wanted)
                if let subject {
                    return try state.place(parsed, windowNumber: subject).summary
                }
                return try state.placeFrontmost(parsed).summary
            }
            if daemon.explain { FileHandle.standardError.write(Data("served by: \(route.rawValue)\n".utf8)) }
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

    struct Focus: ParsableCommand {
        static let configuration =
          CommandConfiguration(abstract: "Switch focus to a direction or window")

        @OptionGroup var options: TargetOptions
        @OptionGroup var daemon: DaemonOptions

        func validate() throws {
            if options.window && options.pid {
                throw ValidationError("--window and --pid are mutually exclusive")
            }
            if options.window || options.pid {
                guard Int32(options.target) != nil else {
                    throw ValidationError("\(options.pid ? "Process" : "Window") id must be an integer")
                }
            } else {
                let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]
                if !validArgs.contains(options.target) {
                    throw ValidationError("Argument must be one of \(validArgs).")
                }
            }
        }

        mutating func run() throws {
            // The pid-compatibility path stays local: it needs to inspect visibleWindows to
            // decide whether the value is a window number or a pid, and it writes a
            // deprecation notice. Routing it through the agent would mean teaching the
            // protocol about a fallback that spikot-win-9ic.3 deletes.
            if options.window {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                try Self.focusWindowOrPID(state, Int(options.target)!)
                return
            }

            let args: [String: String] =
                options.pid ? ["pid": options.target] : ["target": options.target]
            let route = try Client.run(Request(cmd: "focus", args: args), noDaemon: daemon.noDaemon) {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                if self.options.pid {
                    try state.activate(pid: Int32(self.options.target)!)
                } else if self.options.target == "up" || self.options.target == "down" {
                    try state.rotateStack(direction: self.options.target)
                } else {
                    try state.switchStack(toStack: self.options.target)
                }
                return nil
            }
            if daemon.explain { FileHandle.standardError.write(Data("served by: \(route.rawValue)\n".utf8)) }
        }

        /// Resolves `--window <n>` as a window number first, then as a pid.
        ///
        /// The pid path exists only for ~/.local/bin/mylauncher, which reads field 3 of
        /// `spikot-wm list` - the owner pid - and passes it here. The flag has always been
        /// documented as taking a window id while the implementation activated an
        /// application by pid, so both sides were consistently wrong and the pipeline
        /// worked by accident.
        ///
        /// The deprecation notice goes to stderr. mylauncher parses stdout, so anything
        /// written there would break it.
        private static func focusWindowOrPID(_ state: StateCore.State, _ value: Int) throws {
            do {
                try state.focus(windowNumber: value)
                return
            } catch StackError.unknownWindow {
                // Fall through to the pid interpretation.
            }

            guard let pid = Int32(exactly: value),
                state.visibleWindows.contains(where: { $0.kCGWindowOwnerPID == pid })
            else {
                throw StackError.unknownWindow(value)
            }

            let notice =
                "spikot-wm: --window \(value) matched a process id, not a window number."
                + " Use --pid for that, or pass field 1 of `spikot-wm list` for a window."
                + " This fallback is removed in spikot-win-9ic.3.\n"
            FileHandle.standardError.write(Data(notice.utf8))
            try state.activate(pid: pid)
        }
    }
}
