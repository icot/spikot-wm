import Foundation

/// One diagnostic result, for `spikot-wm doctor`.
public struct Check: Sendable {
    public enum Outcome: String, Sendable {
        /// Working.
        case pass = "ok"
        /// Broken, and something will not work because of it.
        case fail = "FAIL"
        /// Worth knowing, but nothing is broken.
        case warn = "warn"
        /// Not applicable yet, for capabilities that are not built.
        case skip = "skip"
    }

    public let name: String
    public let outcome: Outcome
    public let detail: String
    /// Shown under a failing check, when there is something specific to do about it.
    public let remedy: String?

    public init(_ name: String, _ outcome: Outcome, _ detail: String, remedy: String? = nil) {
        self.name = name
        self.outcome = outcome
        self.detail = detail
        self.remedy = remedy
    }
}

/// Collects everything `spikot-wm doctor` reports.
///
/// Each check is independent and none of them throw, so one broken thing does not hide
/// the rest. The system facts arrive through the same injectable sources `State` uses, so
/// every outcome can be exercised in a test - including revoked Accessibility, which
/// cannot be triggered from the CLI.
public struct Diagnostics {

    public static func run(
        config: Config?,
        configError: Error?,
        configPath: String,
        displays: DisplaySource = NSScreenSource(),
        windows: WindowSource = CGWindowSource(),
        accessibilityTrusted: Bool = Accessibility.isTrusted
    ) -> [Check] {
        var checks: [Check] = [
            Check("version", .pass, spikotVersion),
            configCheck(config: config, error: configError, path: configPath),
            accessibilityCheck(trusted: accessibilityTrusted),
            displayCheck(displays.displays()),
            windowCheck(windows.onScreenWindows()),
        ]
        if let config {
            checks.append(cacheCheck(config: config))
        }
        // Reported rather than omitted, so the list matches what the tool will eventually
        // check and a healthy install does not look broken.
        checks.append(
            Check(
                "agent", .skip, "not implemented",
                remedy: "The resident agent arrives in spikot-win-m7t.3."))
        return checks
    }

    private static func configCheck(config: Config?, error: Error?, path: String) -> Check {
        if let error {
            return Check(
                "config", .fail, "\(error)",
                remedy: "Fix or delete \(path); deleting it falls back to defaults.")
        }
        guard let config else {
            return Check("config", .warn, "not loaded")
        }
        let settings = "gap \(config.gap), mode \(config.activeMode)"
        let present = FileManager.default.fileExists(atPath: path)
        return Check(
            "config", .pass,
            present ? "\(path) (\(settings))" : "defaults, no file at \(path) (\(settings))")
    }

    private static func accessibilityCheck(trusted: Bool) -> Check {
        trusted
            ? Check("accessibility", .pass, "this process is trusted")
            : Check(
                "accessibility", .fail, "this process is not trusted",
                remedy: Accessibility.grantInstructions)
    }

    private static func displayCheck(_ screens: [DisplayInfo]) -> Check {
        guard !screens.isEmpty else {
            return Check(
                "displays", .fail, "none reported",
                remedy: "Window placement and stack geometry cannot be computed.")
        }
        let summary = screens.map { screen -> String in
            let size = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
            let origin = "@(\(Int(screen.frame.minX)),\(Int(screen.frame.minY)))"
            return "\(size)\(origin)\(screen.isMain ? " main" : "")"
        }
        return Check("displays", .pass, "\(screens.count): \(summary.joined(separator: ", "))")
    }

    private static func windowCheck(_ visible: [Window]) -> Check {
        visible.isEmpty
            ? Check(
                "windows", .warn, "none on screen",
                remedy: "Expected if the screen is locked or every window is minimised.")
            : Check("windows", .pass, "\(visible.count) on screen")
    }

    private static func cacheCheck(config: Config) -> Check {
        guard config.useCache else {
            return Check("cache", .skip, "disabled by useCache")
        }
        let store = FileStateStore(cachePath: config.cachePath)
        do {
            guard try store.load() != nil else {
                return Check(
                    "cache", .pass, "no cache yet at \(store.location), will be created")
            }
            return Check("cache", .pass, store.location)
        } catch {
            return Check(
                "cache", .fail, "\(store.location) will not decode: \(error)",
                remedy: "Delete it; stack membership is rebuilt from window positions.")
        }
    }

    /// Renders the checks as aligned lines, in the order they were run, with any remedy
    /// indented underneath a failure or warning.
    public static func format(_ checks: [Check]) -> String {
        let width = checks.map(\.name.count).max() ?? 0
        var lines: [String] = []
        for check in checks {
            let name = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("\(name)  [\(check.outcome.rawValue)]  \(check.detail)")
            if check.outcome == .fail || check.outcome == .warn, let remedy = check.remedy {
                for line in remedy.split(separator: "\n") {
                    lines.append("\(String(repeating: " ", count: width))          \(line)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// True when nothing is broken, so the caller can pick an exit code.
    public static func allPassed(_ checks: [Check]) -> Bool {
        !checks.contains { $0.outcome == .fail }
    }
}
