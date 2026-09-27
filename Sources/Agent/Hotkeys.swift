import AppKit
import Carbon.HIToolbox
import StateCore

/// Registers the config's hotkeys and runs the command each one names.
///
/// Carbon `RegisterEventHotKey` rather than the alternatives, for three reasons that all
/// matter here:
///
/// - It *consumes* the keystroke. `NSEvent.addGlobalMonitorForEvents` cannot, so `alt-h`
///   would move the focus and still type an `h` into Emacs.
/// - It needs no TCC permission. `CGEventTap` can consume, but only with Input Monitoring,
///   a second permission prompt on top of Accessibility, and a tap has to re-arm itself
///   after `kCGEventTapDisabledByTimeout`.
/// - It reaches over full-screen apps and across Spaces, and is not deprecated on macOS 26.
///
/// What it cannot do: one global namespace, so no per-application bindings, and no modal or
/// leader-key modes as skhd has.
///
/// It also cannot report a clash with another application. Measured: with this agent holding
/// ctrl-alt-shift-F19, a second process registering the same combination got `noErr`, while
/// registering the same combination twice inside one process got `eventHotKeyExistsErr`
/// (-9878). So that error means a duplicate in our own table, never a conflict with skhd or
/// Rectangle — those simply take the keystroke first and this agent's registration never
/// fires, with nothing in any API to say so.
///
/// MASShortcut was the alternative to hand-rolling this, since Rectangle v2.0 depends on it
/// (`Rectangle/ShortcutManager.swift`). Checked: `MASHotKey.m:21` calls
/// `RegisterEventHotKey([shortcut carbonKeyCode], [shortcut carbonFlags], …)`, so it is the
/// same mechanism wrapped in Objective-C. Not taken, because what it adds beyond this file
/// is `MASShortcutView`, a recorder control, and a `UserDefaults` binding layer — neither of
/// use when bindings come from a config file.
@MainActor
final class HotkeyController {
    /// What happened to one line of the config's `hotkeys` table.
    enum Status: Equatable {
        case bound
        /// Two lines in the table mean the same combination, so only the first can have it.
        /// Carries the key that took it, which is not necessarily spelled the same way:
        /// `cmd-shift-1` and `shift+cmd+1` are one key.
        case duplicate(String)
        /// The spec or the command did not parse. Carries the reason for the menu.
        case rejected(String)
        /// An `exec` binding whose command could not be found when it was registered. The key
        /// is still held, because the command may appear later; this is how a binding pointing
        /// at a missing script becomes visible instead of doing nothing on the keypress.
        case unresolved(String)
        /// Registration failed for another reason, with the `OSStatus`.
        case failed(OSStatus)
        /// `hotkeysEnabled` is false, so nothing was registered.
        case off
    }

    struct Binding {
        /// The config key exactly as written, so the menu shows what the file says.
        let key: String
        let command: String
        let status: Status
    }

    /// Four-character signature Carbon uses to tell one client's hotkey ids from another's.
    /// 'SPKT'.
    private static let signature = OSType(0x5350_4B54)

    /// One key this process currently holds: what it does, and the handle to let it go.
    private struct Live {
        let binding: Binding
        let request: Request
        let ref: EventHotKeyRef
    }

    private let engine: AgentEngine
    /// Registrations by hotkey id, which is what the Carbon event carries.
    private var live: [UInt32: Live] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Every binding in the config, registered or not, in config order. Read by the menu.
    private(set) var bindings: [Binding] = []

    init(engine: AgentEngine) {
        self.engine = engine
    }

    /// Count of bindings that hold a key right now.
    var boundCount: Int { bindings.filter { $0.status == .bound }.count }
    /// Count of bindings that wanted a key and did not get one.
    var problemCount: Int {
        bindings.filter { $0.status != .bound && $0.status != .off }.count
    }

    /// Drops every registration and rebuilds from the current config.
    ///
    /// Called at launch and after any config change, rather than diffing: 17 bindings is
    /// nothing to re-register, and a diff would have to reason about a spec that changed
    /// meaning while keeping its key.
    func sync() {
        unregisterAll()

        let table = engine.settings.hotkeys
        guard engine.settings.hotkeysEnabled else {
            bindings = table.keys.sorted().map {
                Binding(key: $0, command: table[$0] ?? "", status: .off)
            }
            logger.info("Hotkeys disabled; \(bindings.count) binding(s) left unregistered")
            return
        }

        installHandlerIfNeeded()
        // Canonical spelling to the key that claimed it, so the second of two lines meaning
        // the same combination is reported against the first by name.
        var claimed: [String: String] = [:]
        bindings = table.keys.sorted().map { key in
            register(key: key, command: table[key] ?? "", claimed: &claimed)
        }
        logger.info("Hotkeys enabled: \(boundCount) bound, \(problemCount) unavailable")
    }

    private func register(
        key: String, command: String, claimed: inout [String: String]
    ) -> Binding {
        let spec: HotkeySpec
        let request: Request
        do {
            spec = try HotkeySpec.parse(key)
            request = try HotkeyCommand.request(from: command, key: key)
        } catch {
            logger.error("Hotkey '\(key)' ignored: \(error)")
            return Binding(key: key, command: command, status: .rejected("\(error)"))
        }

        if let owner = claimed[spec.canonical] {
            logger.warning("Hotkey '\(key)' repeats '\(owner)' (\(spec.canonical)); ignored")
            return Binding(key: key, command: command, status: .duplicate(owner))
        }

        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode, spec.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), 0, &ref)

        guard status == noErr, let ref else {
            // The duplicate check above should have caught eventHotKeyExistsErr already;
            // reaching it here means two spellings normalised differently, which is a bug in
            // HotkeySpec rather than in the config.
            logger.error("Hotkey \(spec.canonical) could not be registered: OSStatus \(status)")
            return Binding(key: key, command: command, status: .failed(status))
        }

        claimed[spec.canonical] = key
        let binding = Binding(key: key, command: command, status: resolvedStatus(of: request, key: key))
        live[id] = Live(binding: binding, request: request, ref: ref)
        logger.debug("Hotkey \(spec.canonical) -> \(command)")
        return binding
    }

    /// Whether a registered binding will actually be able to do its job.
    ///
    /// Only `exec` has anything to check: its command has to exist. Resolving it here as well
    /// as at run time is what puts a binding pointing at a missing script in front of someone,
    /// instead of leaving a key that quietly does nothing — which is what both of the dead
    /// skhdrc lines had become.
    private func resolvedStatus(of request: Request, key: String) -> Status {
        guard request.cmd == "exec", let line = request.args["command"] else { return .bound }
        do {
            let argv = try ExecCommand.tokenize(line)
            _ = try ExecCommand.resolve(argv[0], searchPath: engine.settings.execPath)
            return .bound
        } catch {
            logger.warning("Hotkey '\(key)' is registered but its command is missing: \(error)")
            return .unresolved("\(error)")
        }
    }

    func unregisterAll() {
        for entry in live.values {
            UnregisterEventHotKey(entry.ref)
        }
        live.removeAll()
        bindings = []
    }

    /// Runs the command a hotkey names, through the same handler the socket uses.
    private func fire(id: UInt32) {
        guard let entry = live[id] else {
            logger.debug("Hotkey id \(id) fired with no binding")
            return
        }
        let response = engine.handle(entry.request)
        if response.ok {
            logger.debug("Hotkey \(entry.binding.key): \(entry.binding.command) ok")
        } else {
            let message = response.error?.message ?? "no detail"
            logger.error("Hotkey \(entry.binding.key): \(entry.binding.command) failed: \(message)")
        }
    }

    /// Installs the one handler all hotkeys are delivered to.
    ///
    /// `GetApplicationEventTarget()` is pumped by `NSApplication.run()`, which is why the
    /// agent has been an `NSApplication` since its first commit: under `dispatchMain()` this
    /// registration succeeds and the handler is never called.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let read = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard read == noErr else { return read }
                // Carbon delivers into the application event target on the main thread, so
                // this closure is already where the engine lives. It is a C function
                // pointer and cannot capture, hence the round trip through userData.
                let controller = Unmanaged<HotkeyController>
                    .fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { controller.fire(id: id.id) }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        if status != noErr {
            logger.error("Could not install the hotkey handler: OSStatus \(status)")
        }
    }
}
