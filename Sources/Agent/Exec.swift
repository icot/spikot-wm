// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StateCore

// Running a command for an `exec` binding, which is the one thing skhd does that has no IPC
// equivalent: eight of the twelve bindings in the user's skhdrc are a key against a command
// line, so without this skhd cannot be retired.
extension AgentEngine {

    /// Starts the command and returns as soon as it is running.
    ///
    /// Deliberately does not wait: a binding that opened Ghostty would otherwise hold the main
    /// actor for as long as the window stayed open, and with it the socket handlers, the menu
    /// and every other hotkey. The exit status is logged by the termination handler instead,
    /// which is the only place it can go — a keypress has no stdout.
    func execResponse(_ request: Request) -> Response {
        guard let line = request.args["command"], !line.isEmpty else {
            return .failure(
                id: request.id, code: "usage", message: "exec needs a command to run")
        }

        do {
            let argv = try ExecCommand.tokenize(line)
            let process = try spawn(argv, describedAs: line)
            return .success(
                id: request.id,
                data: [
                    "pid": String(process.processIdentifier),
                    "path": process.executableURL?.path ?? argv[0],
                ])
        } catch let error as ExecError {
            logger.error("exec '\(line)' failed: \(error)")
            return .failure(id: request.id, code: "notFound", message: "\(error)")
        } catch {
            logger.error("exec '\(line)' failed: \(error)")
            return .failure(id: request.id, code: "failure", message: "\(error)")
        }
    }

    /// Resolves argv[0] on `execPath` and starts it, without waiting.
    ///
    /// Shared by `exec` and both halves of `choose`. `output`, when given, receives the child's
    /// standard output instead of the agent's log; `onExit` runs on the main actor with the exit
    /// status, after the non-zero case has been logged.
    @discardableResult
    func spawn(
        _ argv: [String], describedAs line: String, output: Pipe? = nil,
        onExit: (@MainActor @Sendable (Int32) -> Void)? = nil
    ) throws -> Process {
        let executable = try ExecCommand.resolve(argv[0], searchPath: settings.execPath)

        let process = Process()
        process.executableURL = executable
        process.arguments = Array(argv.dropFirst())
        // The child inherits the agent's environment with PATH replaced, so a script
        // called from a binding finds what the binding itself would. mylauncher needs
        // exactly this: it calls spikot-wm, rg and choose by bare name.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ExecCommand.pathVariable(settings.execPath)
        process.environment = environment
        // stdout and stderr are inherited unless `output` is given, so a command's own output
        // lands in the agent's log files, where `make install-agent` or the formula's `service` block points them.
        if let output { process.standardOutput = output }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            if status != 0 {
                let how = finished.terminationReason == .uncaughtSignal ? "signal" : "exit"
                logger.error("exec '\(line)' ended by \(how) \(status)")
            }
            if let onExit {
                Task { @MainActor in onExit(status) }
            }
        }
        try process.run()

        logger.debug("exec \(executable.path) pid \(process.processIdentifier)")
        return process
    }
}
