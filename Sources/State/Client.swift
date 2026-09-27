import ArgumentParser
import Foundation
import StateCore

/// Runs a command through the agent, falling back to doing it in this process.
///
/// The fallback is what makes the whole agent migration safe. Every keybinding keeps
/// working with the agent stopped, crashed, or not yet installed, so the agent is an
/// optimisation rather than a dependency. spikot-win-1iz.1 removes it once the agent has
/// proven itself.
enum Client {

    /// Where a command was carried out, for `--explain` and for tests.
    enum Route: String {
        case agent
        case inProcess = "in-process"
    }

    /// True when the caller has asked for the in-process path explicitly.
    static var forcedLocal: Bool {
        if ProcessInfo.processInfo.environment["SPIKOT_NO_DAEMON"] != nil { return true }
        return false
    }

    /// Sends `request` to the agent, or runs `local` here when there is no agent.
    ///
    /// Only `IPCError.noDaemon` triggers the fallback. Any other socket problem is reported,
    /// because silently doing the work locally would hide a broken agent.
    @discardableResult
    static func run(
        _ request: Request,
        noDaemon: Bool,
        local: () throws -> String?
    ) throws -> Route {
        if noDaemon || forcedLocal {
            if let text = try local() { print(text) }
            return .inProcess
        }

        do {
            let response = try SocketClient().send(request)
            if let text = response.text, !text.isEmpty { print(text) }
            guard response.ok else {
                let failure = response.error
                // An agent too old to know this command is, for this command, the same as no
                // agent at all. Measured: a v0.17.0 agent answering a `place` request from a
                // v0.20.0 CLI replies "unrecognised command 'place'", which would otherwise
                // make a new subcommand fail outright until the bundle was reinstalled.
                if failure?.code == "unknownCommand" {
                    if let text = try local() { print(text) }
                    return .inProcess
                }
                throw CLIError(
                    message: failure?.message ?? "the agent reported a failure",
                    status: ExitStatus(errorCode: failure?.code ?? ""))
            }
            return .agent
        } catch IPCError.noDaemon {
            // Expected whenever the agent is not running. Not worth a warning: this is the
            // normal path for anyone who has not installed the LaunchAgent.
            if let text = try local() { print(text) }
            return .inProcess
        }
    }
}

/// An error carrying the exit code the CLI should use.
struct CLIError: Error, CustomStringConvertible {
    let message: String
    let status: ExitStatus

    var description: String { message }
}

extension CLIError {
    /// ArgumentParser prints `description` and exits with this code.
    var asExitCode: ExitCode { ExitCode(status.rawValue) }
}
