import Foundation

/// How to start one application, for `spikot-wm launch` (spikot-win-9ic.1).
///
/// Unused until that lands; the key exists now so a config file written today stays
/// valid then.
public struct LaunchApp: Codable, Equatable, Sendable {
    /// Preferred over `command`: bundle identifiers survive app renames and moves.
    public var bundleID: String?
    /// Argument vector, for apps that need one (`emacsclient -c -n -a ""`).
    public var command: [String]?

    public init(bundleID: String? = nil, command: [String]? = nil) {
        self.bundleID = bundleID
        self.command = command
    }
}

/// Effective settings, assembled from defaults, then the config file, then the
/// environment.
///
/// Every key in the file is optional: a missing key keeps its default, so a config file
/// only needs the values being changed, and an empty `{}` is valid.
public struct Config: Codable, Equatable, Sendable {
    /// Pixels between a window and both its neighbours and the screen edge.
    ///
    /// Defaults to 10 to match Rectangle Pro's `gapSize`, so windows placed by either
    /// tool line up. See `Contrib/rectangle-pro-defaults.txt`.
    public var gap: Int
    /// Key into the mode table computed by `State.computeModes`: `twoColumns` or
    /// `threeColumns`.
    public var activeMode: String
    /// State cache location, relative to the home directory.
    public var cachePath: String
    /// Whether to merge the cached stack membership on startup.
    public var useCache: Bool
    /// Default log level, overridden by `SPIKOT_LOG`.
    public var logLevel: String
    /// Hotkey spec to command, e.g. `"alt-h": "focus left"` (spikot-win-1k4.2).
    public var hotkeys: [String: String]
    /// Application name to launch settings (spikot-win-9ic.1).
    public var launch: [String: LaunchApp]

    public init(
        gap: Int = 10,
        activeMode: String = "twoColumns",
        cachePath: String = ".spikot-wm-state.json",
        useCache: Bool = true,
        logLevel: String = "info",
        hotkeys: [String: String] = [:],
        launch: [String: LaunchApp] = [:]
    ) {
        self.gap = gap
        self.activeMode = activeMode
        self.cachePath = cachePath
        self.useCache = useCache
        self.logLevel = logLevel
        self.hotkeys = hotkeys
        self.launch = launch
    }

    /// Settings used when there is no config file.
    public static let standard = Config()

    // Decoding treats every key as optional so that a partial file is valid.
    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config.standard
        self.init(
            gap: try keyed.decodeIfPresent(Int.self, forKey: .gap)
                ?? fallback.gap,
            activeMode: try keyed.decodeIfPresent(String.self, forKey: .activeMode)
                ?? fallback.activeMode,
            cachePath: try keyed.decodeIfPresent(String.self, forKey: .cachePath)
                ?? fallback.cachePath,
            useCache: try keyed.decodeIfPresent(Bool.self, forKey: .useCache)
                ?? fallback.useCache,
            logLevel: try keyed.decodeIfPresent(String.self, forKey: .logLevel)
                ?? fallback.logLevel,
            hotkeys: try keyed.decodeIfPresent([String: String].self, forKey: .hotkeys)
                ?? fallback.hotkeys,
            launch: try keyed.decodeIfPresent([String: LaunchApp].self, forKey: .launch)
                ?? fallback.launch
        )
    }
}

/// Why a config file could not be used. Reported instead of trapping or being ignored.
public enum ConfigError: Error, CustomStringConvertible {
    case unreadable(path: String, underlying: Error)
    case malformed(path: String, underlying: Error)
    case unknownMode(String, known: [String])

    public var description: String {
        switch self {
        case .unreadable(let path, let underlying):
            return "cannot read config at \(path): \(underlying.localizedDescription)"
        case .malformed(let path, let underlying):
            return "config at \(path) is not valid JSON: \(underlying)"
        case .unknownMode(let mode, let known):
            return "unknown activeMode '\(mode)'; known modes are \(known.joined(separator: ", "))"
        }
    }
}

extension Config {
    /// Modes `State.computeModes` knows how to build. Validated at load time so a typo
    /// fails with a message rather than force-unwrapping nil later.
    public static let knownModes = ["twoColumns", "threeColumns"]

    /// `~/.config/spikot-wm/config.json`, or `SPIKOT_CONFIG` when set.
    public static var defaultPath: URL {
        if let override = ProcessInfo.processInfo.environment["SPIKOT_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spikot-wm/config.json")
    }

    /// Builds the effective config: defaults, then the file if present, then the
    /// environment.
    ///
    /// A missing file is not an error. A file that exists but cannot be parsed is, so a
    /// typo changes behaviour visibly instead of silently reverting to defaults.
    public static func load(from path: URL? = nil) throws -> Config {
        let url = path ?? defaultPath
        var config = Config.standard

        if FileManager.default.fileExists(atPath: url.path) {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ConfigError.unreadable(path: url.path, underlying: error)
            }
            do {
                config = try JSONDecoder().decode(Config.self, from: data)
            } catch {
                throw ConfigError.malformed(path: url.path, underlying: error)
            }
        }

        config.applyEnvironment(ProcessInfo.processInfo.environment)

        guard knownModes.contains(config.activeMode) else {
            throw ConfigError.unknownMode(config.activeMode, known: knownModes)
        }
        return config
    }

    /// Environment overrides, applied after the file so a one-off run can differ without
    /// editing it.
    mutating func applyEnvironment(_ env: [String: String]) {
        if let raw = env["SPIKOT_GAP"], let gap = Int(raw) { self.gap = gap }
        if let raw = env["SPIKOT_MODE"], !raw.isEmpty { self.activeMode = raw }
        if let raw = env["SPIKOT_CACHE_PATH"], !raw.isEmpty { self.cachePath = raw }
        if let raw = env["SPIKOT_USE_CACHE"] {
            self.useCache = ["1", "true", "yes"].contains(raw.lowercased())
        }
        if let raw = env["SPIKOT_LOG"], !raw.isEmpty { self.logLevel = raw }
    }

    /// The effective config as pretty JSON, for `spikot-wm config`.
    public func prettyJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
