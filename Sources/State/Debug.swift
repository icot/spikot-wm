import ArgumentParser
import Cocoa
import Foundation
import StateCore

// The `debug` subcommands, split out of main.swift to keep it under the file length limit.
// Nothing here is part of the everyday interface: these exist to answer "what does spikot-wm
// think the displays and windows are", which is most of how the placement work is checked
// without moving a window.
extension SpikotWM {

    /// Diagnostics for the Accessibility layer, not part of the everyday surface.
    struct Debug: ParsableCommand {
        static let configuration = CommandConfiguration(
          abstract: "Inspect how windows map to Accessibility elements",
          subcommands: [
            AxCommand.self, GeometryCommand.self, HistoryCommand.self, IPCServeCommand.self,
          ])
    }

    /// Prints the target rect for every stack, in both vertical conventions.
    ///
    /// The point of showing both: `visibleFrame` arrives measured from the bottom of the
    /// primary display, while the Accessibility API measures from its top, and handing one to
    /// something expecting the other is invisible for a rect that happens to be symmetric.
    struct GeometryCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
          commandName: "geometry",
          abstract: "Show each display and where every stack is placed on it")

        func run() throws {
            let state = StateCore.State(config: try Config.load())
            state.initialize()

            let displays = state.displays()
            let axis = Geometry.flipAxis(displays)
            print("flip axis (primary display maxY): \(Int(axis))")
            print("display  frame                      visibleFrame               main")
            for (index, display) in displays.enumerated() {
                print(
                    [
                        pad(String(index), 8),
                        pad(describe(display.frame), 26),
                        pad(describe(display.visibleFrame), 26),
                        display.isMain ? "yes" : "",
                    ].joined(separator: " "))
            }

            print("")
            print("stack  display  centreX  frame (bottom-left)        axFrame (top-left)")
            for placement in state.stackLayout() {
                print(
                    [
                        pad(String(placement.stack), 6),
                        pad(String(placement.display), 8),
                        pad(String(placement.centreX), 8),
                        pad(describe(placement.frame), 26),
                        pad(describe(placement.axFrame), 26),
                    ].joined(separator: " "))
            }
        }

        private func describe(_ rect: CGRect) -> String {
            "\(Int(rect.width))x\(Int(rect.height))@(\(Int(rect.minX)),\(Int(rect.minY)))"
        }

        private func pad(_ text: String, _ width: Int) -> String {
            text.count >= width
                ? String(text.prefix(width))
                : text.padding(toLength: width, withPad: " ", startingAt: 0)
        }
    }

    /// Shows what the agent remembers about each window: where it was before being placed, and
    /// what was last done to it.
    ///
    /// Only the agent has an answer. The history is per-process and unpersisted, so a CLI run
    /// asking itself would always report nothing.
    struct HistoryCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
          commandName: "history",
          abstract: "Show the agent's per-window restore points and last actions")

        func run() throws {
            try Client.run(Request(cmd: "history"), noDaemon: false) {
                "no agent is running, and the history only exists inside it"
            }
        }
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

    /// Runs an echo server on the IPC socket, so the protocol can be exercised by hand
    /// before the agent implements real handlers.
    ///
    /// Useful with: printf '{"cmd":"ping"}\n' | nc -U <path>
    struct IPCServeCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
          commandName: "ipc-serve",
          abstract: "Serve an echo responder on the IPC socket until interrupted")

        @Option(name: [.customLong("path")], help: "Socket path")
        var path: String = IPC.socketURL.path

        @Option(name: [.customLong("seconds")], help: "Exit after this long; 0 waits forever")
        var seconds: Int = 0

        func run() throws {
            let server = SocketServer(path: path)
            try server.start { request in
                .success(
                    id: request.id,
                    text: "pong cmd=\(request.cmd) args=\(request.args)",
                    data: ["cmd": request.cmd])
            }
            print("listening on \(path)")
            if seconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
                    server.stop()
                    Foundation.exit(0)
                }
            }
            dispatchMain()
        }
    }
}
