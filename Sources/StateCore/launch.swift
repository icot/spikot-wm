import Cocoa
import Foundation

/// How to start an application that is not running.
///
/// Resolution is separate from doing it, so the interesting part can be tested: what actually
/// starts a process is four lines at the end of `State.launch`.
public enum LaunchPlan: Equatable, Sendable {
    /// An argument vector, for an application that is really a client of a running process.
    /// `emacsclient -c -n -a ""` is the case this exists for.
    case command([String])
    /// An application bundle to open.
    case bundle(URL)
    /// Nothing found. Carries what was tried, so the message can say where to look.
    case notFound(searched: [String])

    /// Directories searched for `<Name>.app` when the config says nothing.
    ///
    /// Enough for the four applications the old `mylauncher` knew, and it is why a config entry is
    /// usually unnecessary. Emacs is the exception on this machine: there is no
    /// `/Applications/Emacs.app`, the bundle is inside
    /// `/opt/homebrew/opt/emacs-plus@31/`, and the wanted behaviour is `emacsclient` against the
    /// running daemon rather than a second Emacs — so it is in `Config.defaultLaunch` instead.
    public static let searchDirectories = [
        "/Applications", "~/Applications", "/System/Applications",
        "/System/Applications/Utilities",
    ]

    /// Works out how to start `app`.
    ///
    /// The config wins, then a bundle identifier, then a bundle named after the application. The
    /// old bash `case` covered exactly four applications and its generic fallback grepped a
    /// `~/.apps-cache` that does not exist and only echoed the result, so anything outside those
    /// four never launched at all.
    public static func resolve(
        _ app: String,
        config: Config,
        bundleURL: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileManager: FileManager = .default
    ) -> LaunchPlan {
        var searched: [String] = []

        if let entry = config.launch[app] ?? config.launch.first(where: {
            $0.key.caseInsensitiveCompare(app) == .orderedSame
        })?.value {
            if let command = entry.command, !command.isEmpty { return .command(command) }
            if let identifier = entry.bundleID {
                searched.append(identifier)
                if let url = bundleURL(identifier) { return .bundle(url) }
            }
        }

        for directory in searchDirectories {
            let path = (ExecCommand.expandingTilde(directory) as NSString)
                .appendingPathComponent("\(app).app")
            searched.append(path)
            if fileManager.fileExists(atPath: path) { return .bundle(URL(fileURLWithPath: path)) }
        }
        return .notFound(searched: searched)
    }
}

/// What `launch` did.
public enum LaunchOutcome: Equatable, Sendable {
    /// The application was not running, so it was started.
    case launched(String)
    /// One window, brought forward.
    case focused(window: Int, owner: String)
    /// Several windows; one was brought forward and the rest are listed.
    ///
    /// Choosing between them is `spikot-win-9ic.2`. Until then this matches what
    /// `mylauncher <App> fast` did: take the first and say how many there were.
    case several(window: Int, owner: String, count: Int)

    public var summary: String {
        switch self {
        case .launched(let app):
            return "launched \(app)"
        case .focused(let window, let owner):
            return "focused \(owner) \(window)"
        case .several(let window, let owner, let count):
            return "focused \(owner) \(window), the first of \(count) windows"
        }
    }
}

/// Why a launch could not be carried out.
public enum LaunchError: Error, CustomStringConvertible, Equatable {
    case noApplication(String, searched: [String])
    case failedToStart(String, reason: String)

    public var description: String {
        switch self {
        case .noApplication(let app, let searched):
            return "no application '\(app)': tried " + searched.joined(separator: ", ")
                + "; name it in the config's launch section with a bundleID or a command"
        case .failedToStart(let app, let reason):
            return "could not start \(app): \(reason)"
        }
    }

    public var ipcCode: String {
        switch self {
        case .noApplication: return "notFound"
        case .failedToStart: return "failure"
        }
    }
}

extension State {

    /// Focuses an application's window, or starts it when it has none.
    ///
    /// The replacement for `~/.local/bin/mylauncher`, vendored at `Contrib/mylauncher.sh`. No
    /// `rg`, no `choose`, and no dependence on the caller's `PATH`: window lookup is the same
    /// `CGWindowList` snapshot every other command uses.
    /// `waitForLaunch` blocks until the application has started, which a one-shot CLI process
    /// must do: `NSWorkspace.openApplication` is asynchronous, and a process that returns
    /// immediately after calling it exits before the request is carried out. Measured — the first
    /// version reported "launched TextEdit" three times over while `pgrep -x TextEdit` stayed
    /// empty. The agent passes false, because it is still running when the callback arrives and
    /// blocking its main actor would freeze the socket, the menu and every hotkey.
    /// `raiseWhenSeveral` is false for the agent, which shows the picker instead: raising one
    /// window first and then asking which was wanted would move the wrong window forward for as
    /// long as the panel is up.
    public func launch(
        _ app: String, waitForLaunch: Bool = true, raiseWhenSeveral: Bool = true
    ) throws -> LaunchOutcome {
        let windows = self.windows(ofApplication: app)

        if windows.isEmpty {
            return try start(app, waitForLaunch: waitForLaunch)
        }
        // First in CGWindowList order, which is the window server's front-to-back order, so with
        // several windows this is the frontmost of them.
        let window = windows[0]
        if windows.count == 1 {
            raise(window)
            return .focused(window: window.kCGWindowNumber, owner: window.kCGWindowOwnerName)
        }
        if raiseWhenSeveral { raise(window) }
        return .several(
            window: window.kCGWindowNumber, owner: window.kCGWindowOwnerName,
            count: windows.count)
    }

    /// On-screen windows belonging to an application, by name.
    ///
    /// Exact match first, then a prefix, then a substring, so `spikot-wm launch fire` finds
    /// Firefox while `launch Safari` cannot be stolen by something merely containing "Safari".
    /// `mylauncher` piped the whole listing through `rg`, which matched a window *title* as
    /// readily as an application name.
    public func windows(ofApplication app: String) -> [Window] {
        let wanted = app.lowercased()
        let exact = visibleWindows.filter { $0.kCGWindowOwnerName.lowercased() == wanted }
        if !exact.isEmpty { return exact }
        let prefixed = visibleWindows.filter { $0.kCGWindowOwnerName.lowercased().hasPrefix(wanted) }
        if !prefixed.isEmpty { return prefixed }
        return visibleWindows.filter { $0.kCGWindowOwnerName.lowercased().contains(wanted) }
    }

    /// Starts an application that has no windows.
    private func start(_ app: String, waitForLaunch: Bool) throws -> LaunchOutcome {
        switch LaunchPlan.resolve(app, config: config) {
        case .command(let argv):
            let executable: URL
            do {
                executable = try ExecCommand.resolve(argv[0], searchPath: config.execPath)
            } catch {
                throw LaunchError.failedToStart(app, reason: "\(error)")
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = Array(argv.dropFirst())
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ExecCommand.pathVariable(config.execPath)
            process.environment = environment
            do {
                try process.run()
            } catch {
                throw LaunchError.failedToStart(app, reason: "\(error)")
            }
            logger.debug("Launched \(app) as \(executable.path) pid \(process.processIdentifier)")
            return .launched(app)

        case .bundle(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let finished = DispatchSemaphore(value: 0)
            var failure: Error?
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                failure = error
                if let error { logger.error("Opening \(url.lastPathComponent) failed: \(error)") }
                finished.signal()
            }
            if waitForLaunch {
                // Ten seconds is generous for a cold start and short enough that a keybinding
                // cannot appear to hang. The completion handler arrives on a background queue, so
                // waiting here does not deadlock it.
                if finished.wait(timeout: .now() + 10) == .timedOut {
                    logger.warning("\(url.lastPathComponent) did not report back within 10s")
                } else if let failure {
                    throw LaunchError.failedToStart(app, reason: "\(failure)")
                }
            }
            logger.debug("Opened \(url.path)")
            return .launched(app)

        case .notFound(let searched):
            throw LaunchError.noApplication(app, searched: searched)
        }
    }
}
