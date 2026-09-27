import AppKit
import StateCore

// Menu construction, split from StatusItemController so neither file carries the whole
// class. Everything here runs from menuNeedsUpdate.
extension StatusItemController {

    // MARK: - Sections

    func addAccessibilityWarning(to menu: NSMenu) {
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
    func addStacks(to menu: NSMenu) {
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
    func addModes(to menu: NSMenu) {
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

    func addDisplays(to menu: NSMenu) {
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

    /// Everything editable, in one submenu.
    ///
    /// A submenu rather than more top-level items: the interesting part of the menu is the
    /// stacks, and settings are changed rarely. Only discrete choices are offered here.
    /// Anything free-form — the hotkey table, the launch map, an arbitrary gap — is edited
    /// in the file, which "Open Configuration…" opens.
    func addSettings(to menu: NSMenu) {
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(gapMenu())
        submenu.addItem(logLevelMenu())
        submenu.addItem(ignoredAppsMenu())
        submenu.addItem(.separator())

        let cache = NSMenuItem(title: "Use cached stacks", action: #selector(toggleCache), keyEquivalent: "")
        cache.target = self
        cache.state = engine.settings.useCache ? .on : .off
        cache.toolTip = "Off makes every run derive stacks from window positions alone"
        submenu.addItem(cache)

        let hotkeys = NSMenuItem(
            title: "Hotkeys enabled", action: #selector(toggleHotkeys), keyEquivalent: "")
        hotkeys.target = self
        hotkeys.state = engine.settings.hotkeysEnabled ? .on : .off
        // Nothing grabs keys yet, so say so rather than implying the toggle does something.
        hotkeys.toolTip = "Takes effect once the hotkey backend lands (spikot-win-1k4.1)"
        submenu.addItem(hotkeys)

        settings.submenu = submenu
        menu.addItem(settings)

        let reload = NSMenuItem(
            title: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let edit = NSMenuItem(
            title: "Open Configuration…", action: #selector(openConfig), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
    }

    /// Gap presets, plus the current value when it is not one of them, so a hand-edited
    /// number is visible rather than silently absent.
    func gapMenu() -> NSMenuItem {
        let current = engine.settings.gap
        let item = NSMenuItem(title: "Gap — \(current) px", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        var values = Config.gapPresets
        if !values.contains(current) {
            values.append(current)
            values.sort()
        }
        for value in values {
            let entry = NSMenuItem(title: "\(value) px", action: #selector(setGap(_:)), keyEquivalent: "")
            entry.target = self
            entry.state = (value == current) ? .on : .off
            entry.tag = value
            if value == 10 {
                entry.toolTip = "Matches Rectangle Pro's gapSize, so windows placed by either line up"
            }
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    func logLevelMenu() -> NSMenuItem {
        let current = engine.settings.logLevel
        let item = NSMenuItem(title: "Log level — \(current)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for level in Config.logLevels {
            let entry = NSMenuItem(
                title: level, action: #selector(setLogLevel(_:)), keyEquivalent: "")
            entry.target = self
            entry.state = (level == current) ? .on : .off
            entry.representedObject = level
            submenu.addItem(entry)
        }
        item.submenu = submenu
        item.toolTip = "Applies immediately; SPIKOT_LOG overrides it for a single CLI run"
        return item
    }

    /// Read-only. Editing a list of strings through a menu is worse than editing the file.
    func ignoredAppsMenu() -> NSMenuItem {
        let apps = engine.settings.ignoredApps
        let item = NSMenuItem(
            title: "Unmanaged apps — \(apps.count)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if apps.isEmpty {
            submenu.addItem(Self.disabled("none"))
        } else {
            for app in apps {
                submenu.addItem(Self.disabled(app))
            }
        }
        submenu.addItem(.separator())
        let edit = NSMenuItem(
            title: "Edit in Configuration…", action: #selector(openConfig), keyEquivalent: "")
        edit.target = self
        submenu.addItem(edit)
        item.submenu = submenu
        return item
    }
}
