import AppKit
import StateCore

/// The menu bar item.
///
/// The menu is rebuilt in `menuNeedsUpdate`, so it is only ever assembled when someone
/// opens it. That is why the agent needs no AX observers or polling: a refresh happens on
/// open, which is the same freshness policy the IPC handlers use.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    let engine: AgentEngine
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

    // MARK: - Actions

    @objc func focusWindow(_ sender: NSMenuItem) {
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

    @objc func setMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        apply { $0.activeMode = mode }
    }

    @objc func toggleHotkeys() {
        apply { $0.hotkeysEnabled.toggle() }
    }

    @objc func toggleCache() {
        apply { $0.useCache.toggle() }
    }

    @objc func setGap(_ sender: NSMenuItem) {
        apply { $0.gap = sender.tag }
    }

    /// Goes through the engine rather than `apply`, because the level has to reach the
    /// live log handler as well as the file.
    @objc func setLogLevel(_ sender: NSMenuItem) {
        guard let level = sender.representedObject as? String else { return }
        do {
            try engine.applyLogLevel(level)
        } catch {
            logger.error("Could not set the log level: \(error)")
            Self.warn("Could not set the log level", detail: "\(error)")
        }
    }

    @objc func reloadConfig() {
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
    @objc func openConfig() {
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

    @objc func requestPermission() {
        Accessibility.requestTrust()
    }

    @objc func quit() {
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
    static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// An alert, since an agent with no windows has nowhere else to report a failure.
    static func warn(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
