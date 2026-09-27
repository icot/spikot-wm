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
            // stdout and stderr are inherited, so a command's own output lands in the agent's
            // log files, where `make install-agent` points them.
            process.terminationHandler = { finished in
                guard finished.terminationStatus != 0 else { return }
                let how = finished.terminationReason == .uncaughtSignal ? "signal" : "exit"
                logger.error("exec '\(line)' ended by \(how) \(finished.terminationStatus)")
            }
            try process.run()

            logger.debug("exec \(executable.path) pid \(process.processIdentifier)")
            return .success(
                id: request.id,
                data: ["pid": String(process.processIdentifier), "path": executable.path])
        } catch let error as ExecError {
            logger.error("exec '\(line)' failed: \(error)")
            return .failure(id: request.id, code: "notFound", message: "\(error)")
        } catch {
            logger.error("exec '\(line)' failed: \(error)")
            return .failure(id: request.id, code: "failure", message: "\(error)")
        }
    }
}
