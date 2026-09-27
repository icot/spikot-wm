import AppKit
import Foundation
import StateCore

// One function per command the agent answers, split from Engine.swift to keep that file about the
// agent's state and this one about the protocol. Everything here runs on the main actor, after
// `handle` has refreshed the state.
extension AgentEngine {

    func listResponse(_ request: Request) -> Response {
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
    func focusResponse(_ request: Request) -> Response {
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
    func placeResponse(_ request: Request) -> Response {
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

    /// `launch` focuses an application's window, or starts it when it has none.
    func launchResponse(_ request: Request) -> Response {
        guard let app = request.args["app"], !app.isEmpty else {
            return .failure(
                id: request.id, code: "usage", message: "launch needs an application name")
        }
        do {
            // Not waiting: the agent is still running when the callback arrives, and blocking
            // the main actor here would freeze the socket, the menu and every other hotkey.
            let outcome = try state.launch(app, waitForLaunch: false, raiseWhenSeveral: false)
            if case .several(_, _, let count) = outcome {
                showPicker(for: app)
                return .success(
                    id: request.id, text: "choose between \(count) \(app) windows",
                    data: ["app": app, "windows": String(count)])
            }
            logger.debug("launch \(app): \(outcome.summary)")
            return .success(id: request.id, text: outcome.summary, data: ["app": app])
        } catch let error as LaunchError {
            return .failure(id: request.id, code: error.ipcCode, message: error.description)
        } catch {
            return .failure(id: request.id, code: "failure", message: "\(error)")
        }
    }

    /// `pick` shows the window picker, for one application or for everything on screen.
    ///
    /// This is what `alt-v` was meant to run: it pointed at `~/.local/bin/choosewindow`, which was
    /// never written.
    func pickResponse(_ request: Request) -> Response {
        let app = request.args["app"]
        let candidates =
            app.map { state.windows(ofApplication: $0) }
            ?? state.visibleWindows.filter { !settings.ignoredApps.contains($0.kCGWindowOwnerName) }

        guard !candidates.isEmpty else {
            return .failure(
                id: request.id, code: "notFound",
                message: app.map { "no windows of '\($0)' are on screen" }
                    ?? "no windows are on screen")
        }
        // One window is not a choice; raising it is what was wanted.
        guard candidates.count > 1 else {
            let only = candidates[0]
            do {
                try raise(only)
            } catch {
                return .failure(id: request.id, code: "failure", message: "\(error)")
            }
            return .success(
                id: request.id,
                text: "focused \(only.kCGWindowOwnerName) \(only.kCGWindowNumber)")
        }
        show(candidates)
        return .success(
            id: request.id, text: "choose between \(candidates.count) windows",
            data: ["windows": String(candidates.count)])
    }

    /// Shows the picker for an application's windows.
    private func showPicker(for app: String) {
        show(state.windows(ofApplication: app))
    }

    private func show(_ windows: [Window]) {
        picker.show(windows.map { WindowPicker.Row(window: $0.kCGWindowNumber, label: label(for: $0)) })
    }

    /// Re-reads the config file, so editing it does not need an agent restart.
    func reloadResponse(_ request: Request) -> Response {
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
