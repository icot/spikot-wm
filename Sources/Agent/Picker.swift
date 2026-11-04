// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import AppKit
import StateCore

/// The picker: a floating list, filtered as you type. `pick` and `launch` fill it with windows,
/// `choose` with the output lines of a command.
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
/// **The keyboard path is unverified when the panel is opened over the socket.** The panel draws
/// and is on screen — confirmed through `CGWindowListCopyWindowInfo`: one window at layer 3,
/// 720x164, centred — and the view is the first responder, but the application never became
/// active, so the panel never became key and a synthetic Escape did nothing. Ruled out so far,
/// each checked by reading `NSApp.isActive` and `panel.isKeyWindow` 0.4s after showing:
///
/// - `NSApp.activate()` and the deprecated `activate(ignoringOtherApps:)`
/// - activation policy `.accessory` and `.regular`
/// - activating before and after `makeKeyAndOrderFront`
/// - the style mask with and without `.nonactivatingPanel`
/// - making the view first responder explicitly
/// - an unbundled binary, `.build/SpikotWM.app` run from a shell, and that same bundle started by
///   **launchd** with `AssociatedBundleIdentifiers`, which was the leading hypothesis
///
/// What those share is the one thing left: the request arrived over the socket, with no user input
/// anywhere. macOS refuses activation to an application the user has not interacted with, and a
/// Carbon hotkey handler runs inside our own event loop in response to a real keystroke, which may
/// count where a socket write does not. That is the remaining test, and it needs a finger on a
/// key; see `manual-tests.org`.
@MainActor
final class WindowPicker: NSObject, NSWindowDelegate {
    typealias Row = PickerModel.Row

    /// The configured colours, asked for on every `show` rather than once, so editing the config
    /// and reloading recolours the next panel without an agent restart.
    private let colors: () -> PickerColors
    /// What picking a row does. Set by each `show`.
    private var onPick: (Row) -> Void = { _ in }
    /// Whether 1 to 9 pick a row. Off for a `choose` list, whose entries contain digits — 36 of
    /// the 382 in the password store — so a digit has to reach the filter.
    private var numberKeys = true
    /// Counts `show` calls, so a list that arrives after its panel was dismissed and another one
    /// opened is not put into the new one.
    private(set) var session = 0
    private var panel: PickerPanel?
    private var view: PickerView?
    /// The list, filter and selection, which live in StateCore so they can be tested.
    private var model = PickerModel(rows: [])
    /// The application to put back on Escape, so dismissing changes nothing.
    private var previous: NSRunningApplication?

    /// Rows shown at once. Beyond this the filter is the way through the list, which is faster
    /// than scrolling and needs no scroll view.
    static let visibleRows = 12

    init(colors: @escaping () -> PickerColors) {
        self.colors = colors
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// What the panel is showing.
    var visibleLabels: [String] { model.matches.map(\.label) }

    /// Shows the panel. For windows, one row means there is nothing to choose, so the caller
    /// should not be here; `choose` shows it empty and fills it with `replaceRows` once its
    /// command has answered.
    ///
    /// Has to be called from the hotkey handler itself, not later: the panel can only become key
    /// in response to a keystroke (see the type's documentation), which is why `choose` opens it
    /// before its list exists rather than after.
    @discardableResult
    func show(_ rows: [Row], numberKeys: Bool = true, onPick: @escaping (Row) -> Void) -> Int {
        session += 1
        self.model = PickerModel(rows: rows)
        self.numberKeys = numberKeys
        self.onPick = onPick
        self.previous = NSWorkspace.shared.frontmostApplication

        let panel = self.panel ?? makePanel()
        self.panel = panel
        view?.apply(colors())
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
        // Activation is asynchronous, so the state right here says nothing. Reading it a moment
        // later is how the missing first responder and the nonactivating style mask were both
        // found, and it is what says the panel cannot read the keyboard rather than leaving a list
        // on screen that silently ignores it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak panel] in
            guard let panel, panel.isVisible else { return }
            MainActor.assumeIsolated {
                let key = panel.isKeyWindow
                logger.debug("Picker: active \(NSApp.isActive), key \(key)")
                guard !key else { return }
                // A panel that never became key cannot be dismissed either: it reads no keys, and
                // `windowDidResignKey` cannot fire for a window that was never key, so clicking
                // elsewhere leaves it on screen until the agent restarts. Measured by leaving one
                // there. Taking it down is better than a list nothing can close.
                logger.warning(
                    "Picker could not become the key window, so it cannot read keys; dismissing it")
                self?.dismiss(restoringFocus: false)
            }
        }
        return session
    }

    /// Fills a panel opened by `show`, keeping anything already typed. Ignored if that panel has
    /// been dismissed or replaced since, which `session` tells apart.
    func replaceRows(_ rows: [Row], session: Int) {
        guard session == self.session, isVisible else { return }
        model.replaceRows(rows)
        refresh()
        // Centred again at the new height. `show` centred the empty panel, 52 points tall, and
        // `refresh` only changes the height, which AppKit grows upward from the bottom-left
        // origin. With twelve rows the panel is 388 points tall, and its top landed 362 points
        // above the middle of the screen instead of the 194 a centred panel has, which is where
        // the window picker, centred with its rows already in, puts it.
        panel?.center()
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
        if numberKeys, let digit = Int(characters), digit >= 1, digit <= 9 {
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
        // Down first: raising activates the target's application, and the panel should be gone
        // before that rather than after.
        dismiss(restoringFocus: false)
        logger.debug("Picker chose row \(row.id)")
        onPick(row)
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
        view?.render(
            filter: model.filter, rows: model.matches, selection: model.selection,
            numbered: numberKeys)
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
