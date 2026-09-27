import AppKit
import StateCore

/// The menu bar item.
///
/// The menu is rebuilt in `menuNeedsUpdate`, so it is only ever assembled when someone
/// opens it. That is why the agent needs no AX observers or polling: a refresh happens on
/// open, which is the same freshness policy the IPC handlers use.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let engine: AgentEngine
    private let statusItem: NSStatusItem
    private let onQuit: () -> Void

    init(engine: AgentEngine, onQuit: @escaping () -> Void) {
        self.engine = engine
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // A template image adapts to light and dark menu bars on its own; a coloured one
        // would not. The fallback text matters because an SF Symbol name can be absent on
        // an older system, and an item with neither image nor title is invisible and
        // unclickable.
        if let image = NSImage(
            systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "SpikotWM") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "◧"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt from scratch on every open rather than mutated in place: the stacks, their
    /// members and the window titles can all have changed since the last time.
    func menuNeedsUpdate(_ menu: NSMenu) {
        engine.refresh()
        menu.removeAllItems()

        if !Accessibility.isTrusted {
            addAccessibilityWarning(to: menu)
            menu.addItem(.separator())
        }

        addStacks(to: menu)
        menu.addItem(.separator())
        addModes(to: menu)
        addDisplays(to: menu)
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SpikotWM", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Sections

    private func addAccessibilityWarning(to menu: NSMenu) {
        let warning = NSMenuItem(
            title: "Accessibility permission missing",
            action: #selector(requestPermission), keyEquivalent: "")
        warning.target = self
        if let image = NSImage(
            systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) {
            image.isTemplate = true
            warning.image = image
        }
        warning.toolTip = Accessibility.grantInstructions
        menu.addItem(warning)
    }

    /// One submenu per stack, listing its windows. Clicking a window raises that window.
    private func addStacks(to menu: NSMenu) {
        let stacks = engine.stacks
        guard !stacks.isEmpty else {
            menu.addItem(Self.disabled("No stacks for the current display layout"))
            return
        }

        for (index, stack) in stacks.enumerated() {
            let windows = stack.filter { !engine.settings.ignoredApps.contains($0.kCGWindowOwnerName) }
            let header = NSMenuItem(
                title: "Stack \(index) — \(windows.count) window\(windows.count == 1 ? "" : "s")",
                action: nil, keyEquivalent: "")

            if windows.isEmpty {
                header.isEnabled = false
                menu.addItem(header)
                continue
            }

            let submenu = NSMenu()
            for window in windows {
                let item = NSMenuItem(
                    title: engine.label(for: window), action: #selector(focusWindow(_:)),
                    keyEquivalent: "")
                item.target = self
                // The window number, not the index: the list is rebuilt on every open, so
                // an index would go stale the moment anything changes.
                item.tag = window.kCGWindowNumber
                submenu.addItem(item)
            }
            header.submenu = submenu
            menu.addItem(header)
        }
    }

    /// The stack layout, with a checkmark on the active one.
    private func addModes(to menu: NSMenu) {
        let active = engine.settings.activeMode
        let modes = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in Config.knownModes {
            let item = NSMenuItem(title: mode, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.state = (mode == active) ? .on : .off
            item.representedObject = mode
            submenu.addItem(item)
        }
        modes.submenu = submenu
        menu.addItem(modes)
    }

    private func addDisplays(to menu: NSMenu) {
        let displays = engine.displaySummary()
        let item = NSMenuItem(
            title: "Displays — \(displays.count)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for line in displays {
            submenu.addItem(Self.disabled(line))
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addSettings(to menu: NSMenu) {
        let hotkeys = NSMenuItem(
            title: "Hotkeys enabled", action: #selector(toggleHotkeys), keyEquivalent: "")
        hotkeys.target = self
        hotkeys.state = engine.settings.hotkeysEnabled ? .on : .off
        // Nothing grabs keys yet, so say so rather than implying the toggle does something.
        hotkeys.toolTip = "Takes effect once the hotkey backend lands (spikot-win-1k4.1)"
        menu.addItem(hotkeys)

        menu.addItem(Self.disabled("Gap \(engine.settings.gap) px"))

        let reload = NSMenuItem(
            title: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let edit = NSMenuItem(
            title: "Open Configuration…", action: #selector(openConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
    }

    // MARK: - Actions

    @objc private func focusWindow(_ sender: NSMenuItem) {
        guard let window = engine.stacks.flatMap({ $0 }).first(where: { $0.kCGWindowNumber == sender.tag })
        else {
            logger.debug("Window \(sender.tag) is gone; nothing to raise")
            return
        }
        do {
            try engine.raise(window)
        } catch {
            logger.error("Could not raise window \(sender.tag): \(error)")
        }
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        apply { $0.activeMode = mode }
    }

    @objc private func toggleHotkeys() {
        apply { $0.hotkeysEnabled.toggle() }
    }

    @objc private func reloadConfig() {
        do {
            try engine.reload()
        } catch {
            logger.error("Reload failed: \(error)")
            Self.warn("Could not reload the configuration", detail: "\(error)")
        }
    }

    /// Hands the file to whatever is registered for .json, which is the editor in practice.
    ///
    /// Creates it first when absent: opening a path that does not exist does nothing
    /// visible, which looks like the menu item is broken.
    @objc private func openConfig() {
        let path = Config.defaultPath
        if !FileManager.default.fileExists(atPath: path.path) {
            do {
                try engine.settings.save(to: path)
            } catch {
                Self.warn("Could not create the configuration file", detail: "\(error)")
                return
            }
        }
        NSWorkspace.shared.open(path)
    }

    @objc private func requestPermission() {
        Accessibility.requestTrust()
    }

    @objc private func quit() {
        onQuit()
    }

    /// Saves a config change and reports a failure rather than silently dropping it.
    private func apply(_ change: (inout Config) -> Void) {
        do {
            try engine.update(change)
        } catch {
            logger.error("Could not save the configuration: \(error)")
            Self.warn("Could not save the configuration", detail: "\(error)")
        }
    }

    // MARK: - Helpers

    /// A label, not a control.
    private static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// An alert, since an agent with no windows has nowhere else to report a failure.
    private static func warn(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
