import Foundation

/// The command line of an `exec` binding: an argument vector, resolved against a search path.
///
/// No shell. Every command line this replaces in `~/.config/skhd/skhdrc` is plain argv
/// (`emacsclient -c -n`, `open -n /Applications/Ghostty.app`), and running them directly means
/// no quoting rules beyond the ones here, no `$IFS`, and one less process. A binding that
/// genuinely needs a pipe can name a script.
public enum ExecCommand {

    /// Splits a command line into argv.
    ///
    /// Whitespace separates. Single and double quotes group, and inside them everything is
    /// literal, including whitespace and the other quote character — so `""` is how an empty
    /// argument is written, which `emacsclient -c -n -a ""` needs. There is no backslash
    /// escaping: with quotes available it would only add a second way to say the same thing.
    public static func tokenize(_ line: String) throws -> [String] {
        var argv: [String] = []
        var current = ""
        var quote: Character?
        var started = false

        for character in line {
            if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
                // An empty pair of quotes is still an argument.
                started = true
            } else if character.isWhitespace {
                if started { argv.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if quote != nil { throw ExecError.unterminatedQuote(line) }
        if started { argv.append(current) }
        guard !argv.isEmpty else { throw ExecError.empty }
        return argv
    }

    /// Expands a leading `~`, which is the only shell expansion done anywhere here.
    public static func expandingTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return (path as NSString).expandingTildeInPath
    }

    /// Finds the executable for argv[0].
    ///
    /// A name containing a slash is a path and is used as given; anything else is looked up in
    /// `searchPath`, in order. Resolving rather than handing the name to `posix_spawnp` is what
    /// lets a missing command be reported when the binding is registered instead of on the
    /// keypress.
    public static func resolve(
        _ command: String, searchPath: [String],
        fileManager: FileManager = .default
    ) throws -> URL {
        if command.contains("/") {
            let path = expandingTilde(command)
            guard fileManager.isExecutableFile(atPath: path) else {
                throw ExecError.notExecutable(path)
            }
            return URL(fileURLWithPath: path)
        }
        for directory in searchPath {
            let candidate = (expandingTilde(directory) as NSString)
                .appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        throw ExecError.notFound(command, searchPath: searchPath)
    }

    /// The `PATH` value to hand the child.
    ///
    /// The same list the lookup used, so a script called from a binding finds the same
    /// commands the binding itself would. `mylauncher` is the case that needs it: it calls
    /// `spikot-wm`, `rg` and `choose` by bare name.
    public static func pathVariable(_ searchPath: [String]) -> String {
        searchPath.map(expandingTilde).joined(separator: ":")
    }
}

/// Why an `exec` binding could not be run, or could not be understood in the first place.
public enum ExecError: Error, CustomStringConvertible, Equatable {
    case empty
    case unterminatedQuote(String)
    case notFound(String, searchPath: [String])
    case notExecutable(String)

    public var description: String {
        switch self {
        case .empty:
            return "exec needs a command"
        case .unterminatedQuote(let line):
            return "unterminated quote in '\(line)'"
        case .notFound(let command, let searchPath):
            return "'\(command)' is not on the exec search path ("
                + searchPath.joined(separator: ", ") + "); name it with a path,"
                + " or add its directory to execPath in the config"
        case .notExecutable(let path):
            return "'\(path)' is not an executable file"
        }
    }
}
