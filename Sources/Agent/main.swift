import AppKit
import ArgumentParser
import Logging
import StateCore

/// StateCore keeps its own logger internal, so the agent has its own label.
let logger = Logger(label: "org.traf.spikot-agent")

/// The resident agent.
///
/// At this version it only establishes the process shape and handles permissions. The
/// socket server and live state arrive in spikot-win-m7t.3, the menu bar item in
/// spikot-win-nho.1.
///
/// Two things are settled here rather than retrofitted later:
///
/// It is an `NSApplication` with `.accessory` policy from the start. Carbon
/// `RegisterEventHotKey` (spikot-win-1k4.1) delivers into the Carbon application event
/// target, which `NSApplication.run()` pumps; a plain `dispatchMain()` does not.
///
/// It asks for its own Accessibility permission. Run from a terminal, spikot-wm borrows the
/// terminal's grant, because TCC attributes to the responsible process. Measured: launched
/// from Ghostty, `AXIsProcessTrusted()` is true; the same bundle launched with `open`, where
/// it is its own responsible process, reports false. As a LaunchAgent it is always the
/// latter, so it must ask.
@main
struct Agent {
    static func main() {
        let options = AgentOptions.parseOrExit()
        bootstrapLogging(level: Logger.Level(rawValue: options.logLevel) ?? .info)

        if options.checkPermissions {
            Self.reportPermissions()
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AgentDelegate(requestPermission: !options.noPrompt)
        app.delegate = delegate
        app.run()
    }

    static func reportPermissions() {
        print("accessibility:   \(Accessibility.isTrusted ? "granted" : "missing")")
        print("screenRecording: \(ScreenRecording.isGranted ? "granted" : "missing (not required)")")
        print("bundleId:        \(Bundle.main.bundleIdentifier ?? "nil (not running from a bundle)")")
    }
}

struct AgentOptions: ParsableArguments {
    @Flag(
      name: [.customLong("check-permissions")],
      help: "Report permission state and exit")
    var checkPermissions = false

    @Flag(
      name: [.customLong("no-prompt")],
      help: "Do not show the Accessibility dialog when permission is missing")
    var noPrompt = false

    @Option(name: [.customLong("log-level")], help: "trace, debug, info, warning, error")
    var logLevel = "info"
}

final class AgentDelegate: NSObject, NSApplicationDelegate {
    private let requestPermission: Bool

    init(requestPermission: Bool) {
        self.requestPermission = requestPermission
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        logger.info("spikot-agent \(spikotVersion) started, bundle \(bundleID)")

        if Accessibility.isTrusted {
            logger.info("Accessibility granted")
        } else if requestPermission {
            // Shows the system dialog. Granting takes effect on the NEXT launch, so this
            // run continues without the permission rather than waiting for it.
            logger.warning("Accessibility missing; requesting it")
            Accessibility.requestTrust()
            let how = Accessibility.grantInstructions
            logger.warning("Grant it in System Settings, then restart the agent. \(how)")
        } else {
            logger.warning("Accessibility missing and --no-prompt was given")
        }

        // Terminates cleanly on launchctl kickstart -k and on `kill`.
        signal(SIGTERM) { _ in NSApp.terminate(nil) }
        signal(SIGINT) { _ in NSApp.terminate(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("spikot-agent stopping")
    }
}
