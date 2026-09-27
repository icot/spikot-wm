import Foundation
import Testing

@testable import StateCore

@Suite("Diagnostics")
struct DiagnosticsTests {

    private func outcome(_ checks: [Check], _ name: String) -> Check.Outcome? {
        checks.first { $0.name == name }?.outcome
    }

    /// Points at a socket nothing serves, so the agent check is the same whether or not a
    /// real agent happens to be running on this machine.
    private var noAgent: SocketClient {
        SocketClient(
            path: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("spikot-none-\(UUID().uuidString.prefix(8))/a.sock").path,
            timeout: 1)
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
            accessibilityTrusted: true,
            agentClient: noAgent)

        #expect(Diagnostics.allPassed(checks))
        #expect(outcome(checks, "accessibility") == .pass)
        #expect(outcome(checks, "displays") == .pass)
        #expect(outcome(checks, "windows") == .pass)
        // No agent is listening here, which is a warning rather than a failure: the CLI
        // falls back to running in-process, so nothing is broken.
        #expect(outcome(checks, "agent") == .warn)
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
            accessibilityTrusted: false,
            agentClient: noAgent)

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
            accessibilityTrusted: true,
            agentClient: noAgent)

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
            accessibilityTrusted: true,
            agentClient: noAgent)

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
            accessibilityTrusted: true,
            agentClient: noAgent)

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
            accessibilityTrusted: true,
            agentClient: noAgent)
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

@Suite("Agent check")
struct AgentCheckTests {
    /// Runs a server that replies with whatever ping data the test needs.
    private func withAgent<T>(
        replying data: [String: String]?,
        ok: Bool = true,
        _ body: (SocketClient) throws -> T
    ) throws -> T {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-agent-\(UUID().uuidString.prefix(8))/a.sock").path
        let server = SocketServer(path: path)
        defer { server.stop() }
        try server.start { request in
            ok
                ? .success(id: request.id, text: "pong", data: data)
                : .failure(id: request.id, code: "failure", message: "deliberate")
        }
        return try body(SocketClient(path: path, timeout: 2))
    }

    @Test("A current agent reporting a grant passes")
    func healthyAgent() throws {
        let check = try withAgent(replying: [
            "version": spikotVersion, "pid": "123",
            "accessibility": "granted", "bundleId": "org.traf.spikot-wm",
        ]) { Diagnostics.agentCheck(client: $0) }
        #expect(check.outcome == .pass)
        #expect(check.detail.contains("pid 123"))
    }

    @Test("An agent missing its own grant fails, whatever the caller's state")
    func agentWithoutPermission() throws {
        // The caller inherits a grant from its parent, so only the agent's own answer can
        // reveal this.
        let check = try withAgent(replying: [
            "version": spikotVersion, "pid": "123",
            "accessibility": "missing", "bundleId": "org.traf.spikot-wm",
        ]) { Diagnostics.agentCheck(client: $0) }
        #expect(check.outcome == .fail)
        #expect(check.remedy?.contains("its own grant") == true)
    }

    @Test("An agent outside a bundle warns, since its grant will not survive a rebuild")
    func agentWithoutBundle() throws {
        let check = try withAgent(replying: [
            "version": spikotVersion, "pid": "1", "accessibility": "granted", "bundleId": "none",
        ]) { Diagnostics.agentCheck(client: $0) }
        #expect(check.outcome == .warn)
        #expect(check.detail.contains("not running from the .app bundle"))
    }

    @Test("An agent too old to send the fields is not reported as broken")
    func olderAgentSameVersion() throws {
        // Regression: absent fields were read as negative answers, so a healthy agent built
        // before those fields existed was reported as having no Accessibility permission.
        let check = try withAgent(replying: ["version": spikotVersion, "pid": "7"]) {
            Diagnostics.agentCheck(client: $0)
        }
        #expect(check.outcome == .pass)
        #expect(check.detail.contains("too old to report"))
    }

    @Test("A version mismatch warns and says to reinstall")
    func versionMismatch() throws {
        let check = try withAgent(replying: [
            "version": "0.0.1", "pid": "7", "accessibility": "granted",
            "bundleId": "org.traf.spikot-wm",
        ]) { Diagnostics.agentCheck(client: $0) }
        #expect(check.outcome == .warn)
        #expect(check.detail.contains("this CLI is \(spikotVersion)"))
    }

    @Test("No agent is a warning, not a failure, because the CLI falls back")
    func noAgent() {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-absent-\(UUID().uuidString.prefix(8))/a.sock").path
        let check = Diagnostics.agentCheck(client: SocketClient(path: path, timeout: 1))
        #expect(check.outcome == .warn)
        #expect(check.detail.contains("not running"))
    }

    @Test("An agent that replies with a failure is reported as failing")
    func agentReportsFailure() throws {
        let check = try withAgent(replying: nil, ok: false) { Diagnostics.agentCheck(client: $0) }
        #expect(check.outcome == .fail)
    }
}
