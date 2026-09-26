import Foundation
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
        #expect(config.hotkeys.isEmpty)
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
