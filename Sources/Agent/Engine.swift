import AppKit
import CoreGraphics
import Foundation
import Logging
import StateCore

/// Holds the agent's state and answers IPC requests.
///
/// `@MainActor` on purpose, and decided here rather than later. AppKit, the Accessibility
/// API and Carbon hotkeys (spikot-win-1k4.1) all want the main thread, so putting the state
/// on the same actor means none of them need locks. The socket runs on its own queue and
/// hops here to touch anything.
@MainActor
final class AgentEngine {
    private var config: Config
    private var state: State
    /// Counts refreshes, so `SPIKOT_LOG=debug` can show one per command.
    private(set) var refreshCount = 0
    /// Where each window was before the agent moved it, and what it last did to it.
    ///
    /// Held here because a one-shot `spikot-wm` process has nowhere to keep it: run without the
    /// agent, every press is a first press and `restore` has nothing to go back to. Pruned on
    /// every refresh, and not persisted.
    let history = WindowHistory()

    /// Run after any config change, so the hotkey registrations follow the file.
    ///
    /// A closure rather than a direct reference to the controller: the engine is created
    /// first and knows nothing about hotkeys, and the controller needs the engine to run the
    /// commands its keys name.
    var onConfigChange: (() -> Void)?

    init(config: Config) {
        self.config = config
        self.state = State(config: config)
    }

    /// Rebuilds the state from the window server.
    ///
    /// Every command refreshes rather than relying on change notifications. It costs about a
    /// millisecond, keeps the agent's answers identical to what the one-shot CLI would say,
    /// and removes a whole class of stale-state bugs. `initialize()` recomputes the mode
    /// table too, so attaching or detaching a display is picked up without a restart.
    func refresh() {
        state.initialize()
        refreshCount += 1
        // Window ids are only meaningful while the window exists, so the history follows the
        // window list rather than growing for as long as the agent runs.
        history.prune(keeping: Set(state.visibleWindows.map(\.kCGWindowNumber)))
        logger.debug("Refresh \(refreshCount): \(state.stacks.count) stacks, \(state.visibleWindows.count) windows")
    }

    /// Writes the snapshot so `spikot-wm --no-daemon` and a restarted agent both have a
    /// starting point.
    func persist() {
        state.flushCurrentState()
    }

    // MARK: - What the menu bar item reads

    var settings: Config { config }
    var stacks: [[Window]] { state.stacks }

    /// `owner — title`, or just the owner when there is no title.
    ///
    /// Costs one Accessibility round-trip per window, which is why the menu asks for it
    /// only while it is being built rather than on every refresh.
    func label(for window: Window) -> String {
        guard let title = state.title(for: window), !title.isEmpty else {
            return window.kCGWindowOwnerName
        }
        return "\(window.kCGWindowOwnerName) — \(title)"
    }

    func raise(_ window: Window) throws {
        try state.focus(windowNumber: window.kCGWindowNumber)
    }

    /// One line per attached display.
    func displaySummary() -> [String] {
        NSScreenSource().displays().map { screen in
            let size = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
            return "\(size)\(screen.isMain ? " (main)" : "")"
        }
    }

    /// Applies a change to the config, saves it, and rebuilds the state.
    ///
    /// Saving rather than holding it in memory is what makes a menu toggle survive an
    /// agent restart.
    func update(_ change: (inout Config) -> Void) throws {
        var edited = config
        change(&edited)
        try edited.save()
        config = edited
        state = State(config: edited)
        refresh()
        logger.info("Config updated: gap \(edited.gap), mode \(edited.activeMode), hotkeys \(edited.hotkeysEnabled)")
        onConfigChange?()
    }

    /// Applies the log level without waiting for a restart.
    ///
    /// `LoggingSystem.bootstrap` runs once per process, so the level lives behind
    /// `setSpikotLogLevel` rather than in the handler instance.
    func applyLogLevel(_ level: String) throws {
        guard let parsed = Logger.Level(rawValue: level) else {
            throw ConfigError.unknownLogLevel(level)
        }
        try update { $0.logLevel = level }
        setSpikotLogLevel(parsed)
    }

    /// Re-reads the config file and rebuilds. Returns the loaded config.
    @discardableResult
    func reload() throws -> Config {
        let reloaded = try Config.load()
        config = reloaded
        state = State(config: reloaded)
        // A level edited in the file takes effect on reload, not just on restart.
        if let level = Logger.Level(rawValue: reloaded.logLevel) {
            setSpikotLogLevel(level)
        }
        refresh()
        onConfigChange?()
        return reloaded
    }

    func handle(_ request: Request) -> Response {
        switch request.cmd {
        case "ping":
            // Reports the agent's own permission state, which is the point of asking it
            // rather than checking locally: TCC attributes to the responsible process, so a
            // CLI answer describes the terminal, not the agent.
            return .success(
                id: request.id, text: "pong",
                data: [
                    "version": spikotVersion,
                    "pid": String(ProcessInfo.processInfo.processIdentifier),
                    "refreshes": String(refreshCount),
                    "accessibility": Accessibility.isTrusted ? "granted" : "missing",
                    "bundleId": Bundle.main.bundleIdentifier ?? "none",
                    "stacks": String(state.stacks.count),
                ])

        case "state":
            refresh()
            persist()
            return .success(
                id: request.id, text: state.stacksReport(),
                data: ["stacks": String(state.stacks.count)])

        case "list":
            refresh()
            return listResponse(request)

        case "focus":
            refresh()
            return focusResponse(request)

        case "reload":
            return reloadResponse(request)

        case "exec":
            return execResponse(request)

        case "place":
            refresh()
            return placeResponse(request)

        case "history":
            refresh()
            let lines = history.report()
            return .success(
                id: request.id,
                text: lines.isEmpty ? "no window has been placed yet" : lines.joined(separator: "\n"),
                data: ["windows": String(lines.count)])

        default:
            return .failure(
                id: request.id, code: "unknownCommand",
                message: "unrecognised command '\(request.cmd)'")
        }
    }

    private func listResponse(_ request: Request) -> Response {
        let raw = request.args["format"] ?? ListFormat.legacy.rawValue
        guard let format = ListFormat(rawValue: raw) else {
            return .failure(
                id: request.id, code: "usage",
                message: "unknown format '\(raw)'; expected "
                    + ListFormat.allCases.map(\.rawValue).joined(separator: ", "))
        }
        do {
            return .success(
                id: request.id, text: try state.listWindows(format: format),
                data: ["windows": String(state.visibleWindows.count)])
        } catch {
            return .failure(id: request.id, code: "failure", message: "\(error)")
        }
    }

    /// `focus` takes exactly one of target, window or pid, matching the CLI's flags.
    private func focusResponse(_ request: Request) -> Response {
        do {
            if let raw = request.args["pid"] {
                guard let pid = Int32(raw) else {
                    return .failure(id: request.id, code: "usage", message: "pid must be an integer")
                }
                try state.activate(pid: pid)
            } else if let raw = request.args["window"] {
                guard let number = Int(raw) else {
                    return .failure(
                        id: request.id, code: "usage", message: "window must be an integer")
                }
                try state.focus(windowNumber: number)
            } else if let target = request.args["target"] {
                if target == "up" || target == "down" {
                    try state.rotateStack(direction: target)
                    persist()
                } else {
                    try state.switchStack(toStack: target)
                }
            } else {
                return .failure(
                    id: request.id, code: "usage",
                    message: "focus needs one of target, window or pid")
            }
            return .success(id: request.id)
        } catch let error as StackError {
            return .failure(id: request.id, code: error.ipcCode, message: error.description)
        } catch {
            return .failure(id: request.id, code: "failure", message: "\(error)")
        }
    }

    /// `place` takes an action and, optionally, the window to act on.
    ///
    /// Without `window` it falls back to the frontmost application's first window, which is a
    /// guess when that application has several. Naming the window is the reliable form.
    private func placeResponse(_ request: Request) -> Response {
        guard let raw = request.args["action"] else {
            return .failure(
                id: request.id, code: "usage", message: "place needs an action")
        }
        do {
            let action = try PlacementAction.parse(raw)
            let windowNumber: Int
            if let number = request.args["window"] {
                guard let parsed = Int(number) else {
                    return .failure(
                        id: request.id, code: "usage", message: "window must be an integer")
                }
                windowNumber = parsed
            } else {
                windowNumber = try state.frontmostWindowNumber()
            }

            let result = try state.place(action, windowNumber: windowNumber, history: history)
            logger.debug("Placed \(result.summary)")
            return .success(
                id: request.id, text: result.summary,
                data: [
                    "window": String(result.windowNumber),
                    "action": result.action,
                    "display": String(result.display),
                    "x": String(Int(result.rect.minX)), "y": String(Int(result.rect.minY)),
                    "width": String(Int(result.rect.width)),
                    "height": String(Int(result.rect.height)),
                ])
        } catch let error as PlacementError {
            return .failure(id: request.id, code: error.ipcCode, message: error.description)
        } catch let error as StackError {
            return .failure(id: request.id, code: error.ipcCode, message: error.description)
        } catch {
            return .failure(id: request.id, code: "failure", message: "\(error)")
        }
    }

    /// Re-reads the config file, so editing it does not need an agent restart.
    private func reloadResponse(_ request: Request) -> Response {
        do {
            let reloaded = try reload()
            logger.info("Reloaded config: gap \(reloaded.gap), mode \(reloaded.activeMode)")
            return .success(
                id: request.id, text: try reloaded.prettyJSON(),
                data: ["gap": String(reloaded.gap), "mode": reloaded.activeMode])
        } catch {
            return .failure(id: request.id, code: "config", message: "\(error)")
        }
    }
}
