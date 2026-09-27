import AppKit
import StateCore

/// The window picker: a floating list of windows, filtered as you type.
///
/// Replaces two things at once — the interactive branch of `mylauncher`, which shelled out to
/// `choose-gui`, and `~/.local/bin/choosewindow`, which `alt-v` pointed at and which was never
/// written.
///
/// It belongs in the agent rather than the CLI. The agent is already an `NSApplication` with a run
/// loop and can hold key focus; a CLI drawing a panel would have to become one itself, compete for
/// activation, and would take the panel down again the moment the process exited.
///
/// It is **not** a `.nonactivatingPanel`, which the plan called for. That style mask tells the
/// system the window must not bring its application forward, and a keystroke only ever reaches the
/// active application. So the agent becomes `.regular` and activates while the panel is up, as
/// every other launcher on the platform does, and goes back to `.accessory` on dismiss. Picking
/// raises the chosen window, which activates its own application; Escape puts back whatever was in
/// front before.
///
/// **The keyboard path is unverified.** The panel draws and is on screen — confirmed through
/// `CGWindowListCopyWindowInfo`: one window at layer 3, 720x164, centred — and the view is the
/// first responder, but a shell-launched agent never became the active application in any
/// configuration tried: `NSApp.activate()` and the deprecated `activate(ignoringOtherApps:)`, under
/// `.accessory` and `.regular`, unbundled and bundled, all left `NSApp.isActive` and
/// `panel.isKeyWindow` false, and a synthetic Escape did nothing. That is consistent with the
/// macOS 14 rule that an application not put in front by the user is refused activation, and the
/// missing ingredient is most likely a real keypress reaching an agent that launchd started rather
/// than a socket request from a shell. Settling it needs the installed agent and a finger on a key;
/// see `manual-tests.org`.
@MainActor
final class WindowPicker: NSObject, NSWindowDelegate {
    typealias Row = PickerModel.Row

    private let onPick: (Int) -> Void
    private var panel: PickerPanel?
    private var view: PickerView?
    /// The list, filter and selection, which live in StateCore so they can be tested.
    private var model = PickerModel(rows: [])
    /// The application to put back on Escape, so dismissing changes nothing.
    private var previous: NSRunningApplication?

    /// Rows shown at once. Beyond this the filter is the way through the list, which is faster
    /// than scrolling and needs no scroll view.
    static let visibleRows = 12

    init(onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// What the panel is showing.
    var visibleLabels: [String] { model.matches.map(\.label) }

    /// Shows the panel for a set of windows. One row means there is nothing to choose, so the
    /// caller should not be here.
    func show(_ rows: [Row]) {
        guard !rows.isEmpty else { return }
        self.model = PickerModel(rows: rows)
        self.previous = NSWorkspace.shared.frontmostApplication

        let panel = self.panel ?? makePanel()
        self.panel = panel
        refresh()
        panel.center()

        // An `.accessory` application cannot make itself active on demand: measured, `NSApp
        // .activate()` left `NSApp.isActive` and `panel.isKeyWindow` both false, bundled or not,
        // which is the macOS 14 activation-cooperation rule. Becoming `.regular` for as long as
        // the panel is up is what makes it activatable, and the policy goes back on dismiss so the
        // agent is an accessory again — with no Dock icon — the rest of the time.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // And the view has to be the first responder, or key events reach the panel and stop
        // there. Left out at first, which is exactly how it failed: the panel appeared, Escape did
        // nothing.
        if let view { panel.makeFirstResponder(view) }
        logger.debug("Picker showing \(rows.count) window(s)")
        // Activation is asynchronous, so the state right here says nothing; this reports what
        // actually happened, which is how the missing first responder and the nonactivating style
        // mask were both found.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak panel] in
            guard let panel else { return }
            MainActor.assumeIsolated {
                let bundle = Bundle.main.bundleIdentifier ?? "none"
                let key = panel.isKeyWindow
                logger.debug("Picker state: active \(NSApp.isActive), key \(key), bundle \(bundle)")
            }
        }
    }

    func dismiss(restoringFocus: Bool) {
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        if restoringFocus, let previous, previous.processIdentifier != getpid() {
            previous.activate()
        }
    }

    // MARK: - Keys

    /// Handles one keystroke. Returns false when the key means nothing here, so the panel can beep
    /// rather than swallow it.
    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:  // Escape
            dismiss(restoringFocus: true)
            return true
        case 36, 76:  // Return, keypad Enter
            pickSelected()
            return true
        case 125:  // Down
            move(by: 1)
            return true
        case 126:  // Up
            move(by: -1)
            return true
        case 51:  // Delete
            model.backspace()
            refresh()
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return false
        }
        // 1 to 9 pick a row outright, which is how the old choose-gui list was used.
        if let digit = Int(characters), digit >= 1, digit <= 9 {
            if let row = model.row(forNumberKey: digit) { pick(row) }
            return true
        }
        guard !event.modifierFlags.contains(.command) else { return false }
        model.type(characters)
        refresh()
        return true
    }

    private func move(by offset: Int) {
        model.move(by: offset)
        refresh()
    }

    private func pickSelected() {
        guard let row = model.selected else { return }
        pick(row)
    }

    private func pick(_ row: Row) {
        let window = row.window
        // Down first: raising activates the target's application, and the panel should be gone
        // before that rather than after.
        dismiss(restoringFocus: false)
        logger.debug("Picker chose window \(window)")
        onPick(window)
    }

    // MARK: - Drawing

    private func makePanel() -> PickerPanel {
        let panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 200),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.delegate = self
        // Follows the panel across Spaces rather than being left behind on the one it opened on.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PickerView { [weak self] event in self?.handle(event) ?? false }
        panel.contentView = view
        self.view = view
        return panel
    }

    private func refresh() {
        view?.render(filter: model.filter, rows: model.matches, selection: model.selection)
        guard let panel, let view else { return }
        let height = view.fittingHeight(rows: min(model.matches.count, Self.visibleRows))
        var frame = panel.frame
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    /// Dismissed when something else takes focus, which is what a launcher panel should do.
    func windowDidResignKey(_ notification: Notification) {
        dismiss(restoringFocus: false)
    }
}

/// A borderless panel that can still take key events.
///
/// `canBecomeKey` is false by default for a borderless window, which would leave the picker unable
/// to read a keystroke.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
