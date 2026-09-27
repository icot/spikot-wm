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
    /// Internal rather than private so the command handlers in Engine+Commands.swift can reach it:
    /// `private` is file-scoped, and they are the same type in another file.
    private(set) var state: State
    /// Counts refreshes, so `SPIKOT_LOG=debug` can show one per command.
    private(set) var refreshCount = 0
    /// Where each window was before the agent moved it, and what it last did to it.
    ///
    /// Held here because a one-shot `spikot-wm` process has nowhere to keep it: run without the
    /// agent, every press is a first press and `restore` has nothing to go back to. Pruned on
    /// every refresh, and not persisted.
    let history = WindowHistory()

    /// The window picker, created on first use.
    ///
    /// Held by the engine rather than the delegate because both `launch` and `pick` need it, and
    /// because picking a window is `state.focus`, which the engine owns.
    lazy var picker = WindowPicker { [weak self] window in
        guard let self else { return }
        do {
            try state.focus(windowNumber: window)
        } catch {
            logger.error("Could not focus picked window \(window): \(error)")
        }
    }

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

    /// Answers one request.
    ///
    /// Split in two because the vocabulary outgrew a single switch: the first group reports, the
    /// second acts. Both refresh first — every command works from a fresh window list rather than
    /// from change notifications, which is what keeps the agent's answers identical to the
    /// one-shot CLI's.
    func handle(_ request: Request) -> Response {
        if let response = reportingCommand(request) { return response }
        if let response = actingCommand(request) { return response }
        return .failure(
            id: request.id, code: "unknownCommand",
            message: "unrecognised command '\(request.cmd)'")
    }

    /// Commands that only look: nil when this is not one of them.
    private func reportingCommand(_ request: Request) -> Response? {
        switch request.cmd {
        case "ping":
            // Reports the agent's own permission state, which is the point of asking it rather
            // than checking locally: TCC attributes to the responsible process, so a CLI answer
            // describes the terminal, not the agent.
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

        case "history":
            refresh()
            let lines = history.report()
            return .success(
                id: request.id,
                text: lines.isEmpty ? "no window has been placed yet" : lines.joined(separator: "\n"),
                data: ["windows": String(lines.count)])

        default:
            return nil
        }
    }

    /// Commands that change something: nil when this is not one of them.
    private func actingCommand(_ request: Request) -> Response? {
        switch request.cmd {
        case "focus":
            refresh()
            return focusResponse(request)

        case "place":
            refresh()
            return placeResponse(request)

        case "launch":
            refresh()
            return launchResponse(request)

        case "pick":
            refresh()
            return pickResponse(request)

        case "exec":
            return execResponse(request)

        case "reload":
            return reloadResponse(request)

        default:
            return nil
        }
    }
}
