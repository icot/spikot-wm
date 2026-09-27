import Foundation

/// The wire format between `spikot-wm` and `spikot-agent`.
///
/// One JSON object per line, UTF-8, newline-terminated. A client writes one request, reads
/// one response line, and closes.
///
/// Newline-delimited JSON over a unix socket rather than XPC: a Mach service needs a
/// `MachServices` key in the LaunchAgent plist and correct launchd registration, which
/// couples the transport to the thing most likely to be misconfigured while bringing a
/// daemon up, and there is no `nc` equivalent to poke it with. Not TCP either: the earlier
/// attempt in `Sources/StateCore/server.swift`, removed in 84a175f, was an `NWListener` on
/// port 1234 that failed with POSIX 50, and TCP would expose window management to the
/// network.
public enum IPC {
    /// Wire format version. Bumped only on an incompatible change; a mismatch is rejected
    /// rather than guessed at.
    public static let version = 1

    /// Longest accepted line, so a client cannot make the agent buffer without bound.
    public static let maxLineBytes = 64 * 1024

    /// The commands the agent answers. Must match the switch in `AgentEngine.handle`.
    ///
    /// Listed so a hotkey binding can be rejected when it is written rather than when it is
    /// pressed: `HotkeyCommand.request(from:)` checks against this, which is how the menu
    /// bar can show a binding as broken before anyone tries it.
    public static let commands: Set<String> = ["ping", "state", "list", "focus", "reload", "exec"]

    /// Socket path, under the user's state directory rather than /tmp: /tmp is world
    /// writable, and `sun_path` caps at 104 bytes, which this stays well inside.
    public static var socketURL: URL {
        if let override = ProcessInfo.processInfo.environment["SPIKOT_SOCKET"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/spikot-wm/agent.sock")
    }
}

/// A command sent to the agent.
public struct Request: Codable, Equatable, Sendable {
    /// Wire format version, checked by the agent.
    public var version: Int
    /// Echoed back, so a client can be sure a response is its own.
    public var id: String
    public var cmd: String
    /// Command arguments. Deliberately loose: the vocabulary grows with the CLI, and a
    /// strict enum here would mean a wire break every time a flag is added.
    public var args: [String: String]

    public init(
        cmd: String,
        args: [String: String] = [:],
        id: String = UUID().uuidString,
        version: Int = IPC.version
    ) {
        self.version = version
        self.id = id
        self.cmd = cmd
        self.args = args
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case id
        case cmd
        case args
    }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try keyed.decodeIfPresent(Int.self, forKey: .version) ?? IPC.version
        self.id = try keyed.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.cmd = try keyed.decode(String.self, forKey: .cmd)
        self.args = try keyed.decodeIfPresent([String: String].self, forKey: .args) ?? [:]
    }
}

/// The agent's reply.
///
/// `text` carries the exact bytes the CLI should print, and `data` the same information in
/// a machine-readable form. That split is what lets the agent reproduce today's output
/// byte for byte while still exposing correct fields: the client's job becomes "print
/// `text`, exit on `error.code`".
public struct Response: Codable, Equatable, Sendable {
    public struct Failure: Codable, Equatable, Sendable {
        public var code: String
        public var message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public var version: Int
    public var id: String
    public var ok: Bool
    public var text: String?
    public var data: [String: String]?
    public var error: Failure?

    public init(
        id: String,
        ok: Bool,
        text: String? = nil,
        data: [String: String]? = nil,
        error: Failure? = nil,
        version: Int = IPC.version
    ) {
        self.version = version
        self.id = id
        self.ok = ok
        self.text = text
        self.data = data
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case id
        case ok
        case text
        case data
        case error
    }

    public static func success(
        id: String, text: String? = nil, data: [String: String]? = nil
    ) -> Response {
        Response(id: id, ok: true, text: text, data: data)
    }

    public static func failure(id: String, code: String, message: String) -> Response {
        Response(id: id, ok: false, error: Failure(code: code, message: message))
    }
}

/// Exit codes the CLI uses, so a script can tell the cases apart.
public enum ExitStatus: Int32, Sendable {
    case ok = 0
    case failure = 1
    /// ArgumentParser already uses 2 for a usage error.
    case usage = 2
    case noDaemon = 3
    case noPermission = 4
    case notFound = 5
    case config = 78  // EX_CONFIG

    /// Maps a `Response.Failure.code` onto an exit code.
    public init(errorCode: String) {
        switch errorCode {
        case "noDaemon": self = .noDaemon
        case "noPermission": self = .noPermission
        case "notFound", "unknownWindow", "unknownProcess", "emptyStack", "stackOutOfRange":
            self = .notFound
        case "config": self = .config
        default: self = .failure
        }
    }
}

/// Why an IPC exchange failed, as distinct from a command failing.
public enum IPCError: Error, CustomStringConvertible, Equatable {
    case noDaemon(path: String)
    case socketFailure(String)
    case lineTooLong(Int)
    case malformed(String)
    case versionMismatch(got: Int, expected: Int)
    case timedOut

    public var description: String {
        switch self {
        case .noDaemon(let path):
            return "no agent listening at \(path)"
        case .socketFailure(let detail):
            return "socket error: \(detail)"
        case .lineTooLong(let bytes):
            return "message exceeds \(IPC.maxLineBytes) bytes (\(bytes))"
        case .malformed(let detail):
            return "malformed message: \(detail)"
        case .versionMismatch(let got, let expected):
            return "protocol version \(got) is not \(expected)"
        case .timedOut:
            return "the agent did not reply in time"
        }
    }
}
