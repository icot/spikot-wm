import AppKit
import CoreGraphics
import Foundation
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
    }

    /// Re-reads the config file and rebuilds. Returns the loaded config.
    @discardableResult
    func reload() throws -> Config {
        let reloaded = try Config.load()
        config = reloaded
        state = State(config: reloaded)
        refresh()
        return reloaded
    }

    func handle(_ request: Request) -> Response {
        switch request.cmd {
        case "ping":
            return .success(
                id: request.id, text: "pong",
                data: [
                    "version": spikotVersion,
                    "pid": String(ProcessInfo.processInfo.processIdentifier),
                    "refreshes": String(refreshCount),
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
