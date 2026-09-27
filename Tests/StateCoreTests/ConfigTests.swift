import Foundation
import Logging
import Testing

@testable import StateCore

@Suite("Configuration")
struct ConfigTests {

    @Test("Defaults match what the tools shipped with")
    func defaults() {
        let config = Config.standard
        // 10 to match Rectangle Pro's gapSize; see Contrib/rectangle-pro-defaults.txt.
        #expect(config.gap == 10)
        #expect(config.activeMode == "twoColumns")
        #expect(config.cachePath == ".spikot-wm-state.json")
        #expect(config.useCache)
        // The four stack-focus keys ship bound but switched off; see Contrib/hotkeys.md for
        // the rest and why they are not here.
        #expect(config.hotkeys == Config.defaultHotkeys)
        #expect(!config.hotkeysEnabled, "installing must not take keys away from skhd")
        #expect(config.launch.isEmpty)
    }

    @Test("An empty object is valid and yields the defaults")
    func emptyObject() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(config == Config.standard)
    }

    @Test("A partial file overrides only the keys it names")
    func partialFile() throws {
        let json = #"{"gap": 42, "activeMode": "threeColumns"}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.gap == 42)
        #expect(config.activeMode == "threeColumns")
        #expect(config.cachePath == Config.standard.cachePath, "untouched keys keep defaults")
        #expect(config.useCache == Config.standard.useCache)
    }

    @Test("Unknown keys are ignored rather than rejected")
    func unknownKeys() throws {
        let json = #"{"gap": 5, "somethingFromALaterVersion": true}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.gap == 5)
    }

    @Test("Launch entries decode")
    func launchEntries() throws {
        let json = """
            {"launch": {"Firefox": {"bundleID": "org.mozilla.firefox"},
                        "Emacs": {"command": ["emacsclient", "-c", "-n"]}}}
            """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.launch["Firefox"]?.bundleID == "org.mozilla.firefox")
        #expect(config.launch["Emacs"]?.command == ["emacsclient", "-c", "-n"])
    }

    @Test("A missing file is not an error")
    func missingFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-no-config-\(UUID().uuidString).json")
        let config = try Config.load(from: url)
        #expect(config.activeMode == Config.standard.activeMode)
    }

    @Test("Malformed JSON reports the path instead of silently using defaults")
    func malformedFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-bad-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"gap":"#.utf8).write(to: url)

        #expect(throws: ConfigError.self) { _ = try Config.load(from: url) }
    }

    @Test("An unknown mode is caught at load, not force-unwrapped later")
    func unknownMode() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-mode-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"activeMode": "fourColumns"}"#.utf8).write(to: url)

        #expect(throws: ConfigError.self) { _ = try Config.load(from: url) }
    }

    @Test("Environment values override the file")
    func environmentOverrides() {
        var config = Config(gap: 1, activeMode: "twoColumns")
        config.applyEnvironment([
            "SPIKOT_GAP": "33",
            "SPIKOT_MODE": "threeColumns",
            "SPIKOT_USE_CACHE": "false",
            "SPIKOT_LOG": "debug",
        ])
        #expect(config.gap == 33)
        #expect(config.activeMode == "threeColumns")
        #expect(!config.useCache)
        #expect(config.logLevel == "debug")
    }

    @Test("A non-numeric SPIKOT_GAP is ignored rather than resetting the gap")
    func badEnvironmentGap() {
        var config = Config(gap: 7)
        config.applyEnvironment(["SPIKOT_GAP": "wide"])
        #expect(config.gap == 7)
    }
}

@Suite("Window decoding")
struct WindowDecodingTests {

    @Test("A complete CGWindowList entry decodes")
    func complete() {
        let entry: [String: Any] = [
            "kCGWindowAlpha": 1,
            "kCGWindowBounds": ["Height": 800, "Width": 756, "X": 0, "Y": 0],
            "kCGWindowIsOnscreen": 1,
            "kCGWindowLayer": 0,
            "kCGWindowMemoryUsage": 2288,
            "kCGWindowNumber": 42,
            "kCGWindowOwnerName": "Emacs",
            "kCGWindowOwnerPID": Int32(123),
            "kCGWindowSharingState": 0,
            "kCGWindowStoreType": 1,
        ]
        let window = Window(dict: entry)
        #expect(window?.kCGWindowNumber == 42)
        #expect(window?.kCGWindowOwnerName == "Emacs")
    }

    @Test("A missing key yields nil instead of trapping")
    func missingKey() {
        // kCGWindowOwnerName absent, which happens for some windows.
        let entry: [String: Any] = [
            "kCGWindowAlpha": 1,
            "kCGWindowBounds": ["Height": 800, "Width": 756, "X": 0, "Y": 0],
            "kCGWindowLayer": 0,
            "kCGWindowMemoryUsage": 2288,
            "kCGWindowNumber": 42,
            "kCGWindowOwnerPID": Int32(123),
            "kCGWindowSharingState": 0,
            "kCGWindowStoreType": 1,
        ]
        #expect(Window(dict: entry) == nil)
    }

    @Test("kCGWindowIsOnscreen defaults to 0 when absent")
    func onscreenOptional() {
        let entry: [String: Any] = [
            "kCGWindowAlpha": 1,
            "kCGWindowBounds": ["Height": 800, "Width": 756, "X": 0, "Y": 0],
            "kCGWindowLayer": 0,
            "kCGWindowMemoryUsage": 2288,
            "kCGWindowNumber": 42,
            "kCGWindowOwnerName": "Emacs",
            "kCGWindowOwnerPID": Int32(123),
            "kCGWindowSharingState": 0,
            "kCGWindowStoreType": 1,
        ]
        #expect(Window(dict: entry)?.kCGWindowIsOnscreen == 0)
    }

    @Test("Malformed bounds reject the whole entry")
    func badBounds() {
        let entry: [String: Any] = [
            "kCGWindowAlpha": 1,
            "kCGWindowBounds": ["Height": 800, "Width": 756],
            "kCGWindowLayer": 0,
            "kCGWindowMemoryUsage": 2288,
            "kCGWindowNumber": 42,
            "kCGWindowOwnerName": "Emacs",
            "kCGWindowOwnerPID": Int32(123),
            "kCGWindowSharingState": 0,
            "kCGWindowStoreType": 1,
        ]
        #expect(Window(dict: entry) == nil)
    }
}

@Suite("Editable settings")
struct EditableSettingsTests {

    @Test("Every gap preset and log level the menu offers is a valid config value")
    func presetsAreValid() throws {
        for gap in Config.gapPresets {
            let json = #"{"gap": \#(gap)}"#
            #expect(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).gap == gap)
        }
        for level in Config.logLevels {
            let json = #"{"logLevel": "\#(level)"}"#
            #expect(try JSONDecoder().decode(Config.self, from: Data(json.utf8)).logLevel == level)
        }
    }

    @Test("Every log level the menu offers is one swift-log understands")
    func logLevelsParse() {
        // The menu writes these straight into setSpikotLogLevel, so an entry swift-log does
        // not recognise would be an item that silently does nothing.
        for level in Config.logLevels {
            #expect(Logger.Level(rawValue: level) != nil, "swift-log rejects '\(level)'")
        }
        #expect(Config.logLevels.count == Logger.Level.allCases.count, "no level is missing")
    }

    @Test("The default gap is one of the presets, so the menu shows it checked")
    func defaultGapIsPresent() {
        #expect(Config.gapPresets.contains(Config.standard.gap))
    }

    @Test("A config round-trips through save and load")
    func saveLoadRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-cfg-\(UUID().uuidString)/config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = Config(
            gap: 20, activeMode: "threeColumns", logLevel: "debug", hotkeysEnabled: true,
            ignoredApps: ["borders", "Dock"])
        try original.save(to: url)
        #expect(try Config.load(from: url) == original)
    }

    @Test("Saving creates the directory, since a fresh machine has no ~/.config/spikot-wm")
    func saveCreatesDirectory() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-new-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Config.standard.save(to: dir.appendingPathComponent("nested/config.json"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("nested/config.json").path))
    }

    @Test("Missing default bindings can be added without touching the others")
    func addMissingHotkeys() {
        // The case this exists for: a file saved before the defaults existed holds an explicit
        // empty table, which decoding keeps empty.
        var config = Config(hotkeys: [:])
        #expect(config.missingDefaultHotkeys.count == Config.defaultHotkeys.count)
        config.addMissingDefaultHotkeys()
        #expect(config.hotkeys == Config.defaultHotkeys)
        #expect(config.missingDefaultHotkeys.isEmpty)
    }

    @Test("Adding the defaults leaves a rebound key pointing where the user put it")
    func addMissingKeepsEdits() {
        var config = Config(hotkeys: ["alt-h": "state", "cmd-shift-f19": "reload"])
        config.addMissingDefaultHotkeys()
        #expect(config.hotkeys["alt-h"] == "state", "an edited binding is not overwritten")
        #expect(config.hotkeys["cmd-shift-f19"] == "reload", "an extra binding is not removed")
        #expect(config.hotkeys["alt-l"] == "focus right", "the missing ones are added")
        #expect(config.hotkeys.count == Config.defaultHotkeys.count + 1)
    }

    @Test("An unparseable log level is reported rather than accepted")
    func badLogLevel() {
        #expect(Logger.Level(rawValue: "chatty") == nil)
        #expect(!Config.logLevels.contains("chatty"))
    }
}
