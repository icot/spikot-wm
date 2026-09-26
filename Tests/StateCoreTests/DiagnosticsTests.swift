import Foundation
import Testing

@testable import StateCore

@Suite("Diagnostics")
struct DiagnosticsTests {

    private func outcome(_ checks: [Check], _ name: String) -> Check.Outcome? {
        checks.first { $0.name == name }?.outcome
    }

    @Test("A healthy setup passes everything that is implemented")
    func healthy() {
        let checks = Diagnostics.run(
            config: Config(useCache: false),
            configError: nil,
            configPath: "/nonexistent/config.json",
            displays: FakeDisplaySource(list: Fixtures.laptopPlusUltrawide),
            windows: FakeWindowSource(windows: [
                Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
            ]),
            accessibilityTrusted: true)

        #expect(Diagnostics.allPassed(checks))
        #expect(outcome(checks, "accessibility") == .pass)
        #expect(outcome(checks, "displays") == .pass)
        #expect(outcome(checks, "windows") == .pass)
        // The resident agent does not exist yet, so it is reported as skipped rather than
        // failing and making a healthy install look broken.
        #expect(outcome(checks, "agent") == .skip)
    }

    @Test("Revoked Accessibility fails and explains how to grant it")
    func accessibilityRevoked() {
        // Cannot be exercised through the CLI: revoking the permission needs System
        // Settings. Injecting it is the point of the parameter.
        let checks = Diagnostics.run(
            config: Config(useCache: false),
            configError: nil,
            configPath: "/nonexistent/config.json",
            displays: FakeDisplaySource(list: Fixtures.laptopOnly),
            windows: FakeWindowSource(windows: []),
            accessibilityTrusted: false)

        #expect(!Diagnostics.allPassed(checks))
        #expect(outcome(checks, "accessibility") == .fail)
        let remedy = checks.first { $0.name == "accessibility" }?.remedy
        #expect(remedy?.contains("System Settings") == true)
    }

    @Test("A broken config fails but the other checks still run")
    func brokenConfig() {
        let checks = Diagnostics.run(
            config: nil,
            configError: ConfigError.unknownMode("fourColumns", known: Config.knownModes),
            configPath: "/tmp/broken.json",
            displays: FakeDisplaySource(list: Fixtures.laptopOnly),
            windows: FakeWindowSource(windows: []),
            accessibilityTrusted: true)

        #expect(!Diagnostics.allPassed(checks))
        #expect(outcome(checks, "config") == .fail)
        #expect(outcome(checks, "displays") == .pass, "one failure must not hide the rest")
        #expect(outcome(checks, "accessibility") == .pass)
    }

    @Test("No displays is a failure, since no geometry can be computed")
    func noDisplays() {
        let checks = Diagnostics.run(
            config: Config(useCache: false),
            configError: nil,
            configPath: "/nonexistent/config.json",
            displays: FakeDisplaySource(list: []),
            windows: FakeWindowSource(windows: []),
            accessibilityTrusted: true)

        #expect(!Diagnostics.allPassed(checks))
        #expect(outcome(checks, "displays") == .fail)
    }

    @Test("No windows is a warning, not a failure")
    func noWindows() {
        // Normal with the screen locked or everything minimised, so it must not make
        // doctor exit non-zero.
        let checks = Diagnostics.run(
            config: Config(useCache: false),
            configError: nil,
            configPath: "/nonexistent/config.json",
            displays: FakeDisplaySource(list: Fixtures.laptopOnly),
            windows: FakeWindowSource(windows: []),
            accessibilityTrusted: true)

        #expect(outcome(checks, "windows") == .warn)
        #expect(Diagnostics.allPassed(checks))
    }

    @Test("useCache false skips the cache check")
    func cacheDisabled() {
        let checks = Diagnostics.run(
            config: Config(useCache: false),
            configError: nil,
            configPath: "/nonexistent/config.json",
            displays: FakeDisplaySource(list: Fixtures.laptopOnly),
            windows: FakeWindowSource(windows: []),
            accessibilityTrusted: true)
        #expect(outcome(checks, "cache") == .skip)
    }

    @Test("The report names every check and marks the failing ones")
    func formatting() {
        let checks = [
            Check("version", .pass, "0.0.0"),
            Check("accessibility", .fail, "not trusted", remedy: "Grant it in Settings."),
        ]
        let text = Diagnostics.format(checks)
        #expect(text.contains("version"))
        #expect(text.contains("[FAIL]"))
        #expect(text.contains("Grant it in Settings."), "the remedy is shown under a failure")
    }

    @Test("A remedy on a passing check is not printed")
    func remedyOnlyOnProblems() {
        let text = Diagnostics.format([Check("version", .pass, "0.0.0", remedy: "unused")])
        #expect(!text.contains("unused"))
    }
}
