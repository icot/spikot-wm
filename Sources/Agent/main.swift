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

        let config: Config
        do {
            config = try Config.load()
        } catch {
            FileHandle.standardError.write(Data("spikot-agent: \(error)\n".utf8))
            exit(ExitStatus.config.rawValue)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AgentDelegate(
            config: config,
            socketPath: options.socketPath,
            requestPermission: !options.noPrompt)
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

    @Option(name: [.customLong("socket")], help: "IPC socket path")
    var socketPath: String = IPC.socketURL.path
}

final class AgentDelegate: NSObject, NSApplicationDelegate {
    private let config: Config
    private let socketPath: String
    private let requestPermission: Bool
    private var engine: AgentEngine?
    private var server: SocketServer?
    /// Held so the sources are not cancelled by going out of scope.
    private var signalSources: [DispatchSourceSignal] = []

    init(config: Config, socketPath: String, requestPermission: Bool) {
        self.config = config
        self.socketPath = socketPath
        self.requestPermission = requestPermission
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "none"
        logger.info("spikot-agent \(spikotVersion) started, bundle \(bundleID)")
        checkPermission()

        let engine = AgentEngine(config: config)
        engine.refresh()
        self.engine = engine

        let server = SocketServer(path: socketPath)
        do {
            // The handler runs on the socket queue. Hopping to the main queue is what keeps
            // every AppKit, Accessibility and state access on one actor without locks;
            // assumeIsolated is sound because DispatchQueue.main.sync runs it on the main
            // thread. main is pumping NSApp.run(), so it cannot be blocked waiting on us.
            try server.start { request in
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated { engine.handle(request) }
                }
            }
        } catch {
            logger.error("Cannot serve on \(self.socketPath): \(error)")
            exit(ExitStatus.failure.rawValue)
        }
        self.server = server

        Self.watchDisplays()
        installSignalHandlers()
    }

    private func checkPermission() {
        if Accessibility.isTrusted {
            logger.info("Accessibility granted")
            return
        }
        guard requestPermission else {
            logger.warning("Accessibility missing and --no-prompt was given")
            return
        }
        // Shows the system dialog. Granting takes effect on the NEXT launch, so this run
        // continues without the permission rather than waiting for it.
        logger.warning("Accessibility missing; requesting it")
        Accessibility.requestTrust()
        let how = Accessibility.grantInstructions
        logger.warning("Grant it, then restart the agent. \(how)")
    }

    /// Logs display attach and detach.
    ///
    /// Not needed for correctness: every command calls `refresh()`, which recomputes the
    /// mode table, so a display change is picked up on the next command regardless. This
    /// exists so the change is visible in the log, and as the hook for re-tiling on
    /// reconfiguration later.
    ///
    /// The callback is a C function pointer and cannot capture, which is why it only logs.
    private static func watchDisplays() {
        CGDisplayRegisterReconfigurationCallback(
            { display, flags, _ in
                if flags.contains(.addFlag) {
                    logger.info("Display \(display) attached")
                } else if flags.contains(.removeFlag) {
                    logger.info("Display \(display) removed")
                } else if flags.contains(.setModeFlag) {
                    logger.info("Display \(display) changed mode")
                }
            }, nil)
    }

    /// Terminates through AppKit so applicationWillTerminate runs and the socket is removed.
    ///
    /// `launchctl kickstart -k` sends SIGTERM, and the default disposition would exit
    /// without unlinking the socket, leaving a stale path for the next start.
    ///
    /// DispatchSourceSignal rather than `signal(2)`: a real signal handler runs in signal
    /// context, where only async-signal-safe calls are allowed, and NSApp.terminate is a
    /// long way from that. A dispatch source delivers on the main queue instead, so the
    /// handler is ordinary main-thread code. The signals are ignored first, or the default
    /// disposition kills the process before the source ever fires.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                // Queued on .main, so this is the main thread; the closure type is still
                // nonisolated, which is what assumeIsolated settles.
                MainActor.assumeIsolated {
                    logger.info("Received signal \(number); terminating")
                    NSApp.terminate(nil)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        logger.info("spikot-agent stopping")
    }
}
