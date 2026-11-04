// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

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
        Launch.self,
        ConfigCommand.self,
        Doctor.self,
        Debug.self,
      ],
      defaultSubcommand: State.self)

}

struct TargetOptions: ParsableArguments {

    @Flag(
      name: [.customLong("window"), .customShort("w")],
      help: "Treat the target as a window number")
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
        var format: ListFormat = .tsv

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
          abstract: "Move a window to a stack, a fraction of the screen, or another display")

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

    /// Focuses an application, or starts it when it is not running.
    ///
    /// The replacement for `~/.local/bin/mylauncher`, which needed `rg`, `choose` and a PATH that
    /// found `spikot-wm` by bare name. None of that applies here.
    struct Launch: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Focus an application's window, or start it if it has none")

        @Argument(help: "Application name, as `spikot-wm list` reports it")
        var app: String

        @OptionGroup var daemon: DaemonOptions

        mutating func run() throws {
            let wanted = app
            let route = try Client.run(
                Request(cmd: "launch", args: ["app": wanted]), noDaemon: daemon.noDaemon
            ) {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                return try state.launch(wanted).summary
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
            if options.pid {
                guard Int32(options.target) != nil else {
                    throw ValidationError("Process id must be an integer")
                }
            } else if options.window {
                guard Int(options.target) != nil else {
                    throw ValidationError("Window id must be an integer")
                }
            } else {
                let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]
                if !validArgs.contains(options.target) {
                    throw ValidationError("Argument must be one of \(validArgs).")
                }
            }
        }

        mutating func run() throws {
            let args: [String: String]
            if options.window {
                args = ["window": options.target]
            } else if options.pid {
                args = ["pid": options.target]
            } else {
                args = ["target": options.target]
            }
            let route = try Client.run(Request(cmd: "focus", args: args), noDaemon: daemon.noDaemon) {
                let state = StateCore.State(config: try Config.load())
                state.initialize()
                if self.options.window {
                    try state.focus(windowNumber: Int(self.options.target)!)
                } else if self.options.pid {
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
    }
}
