// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

// The on-screen parts of a demo recording: a key display and a plain backdrop.
//
// Reads lines from stdin, each `<keys><TAB><caption>`, and shows the keys as key caps with the
// caption under it, at the bottom of the main display. Keys are written as in the config
// (`cmd-shift-3`), several separated by spaces (`down down return`), and may be empty for a step
// with no binding. A line reading `clear` takes the display down; otherwise it fades out `hold`
// seconds after the last line.
//
// The backdrop covers every display just above the desktop icons, so the icons and the desktop
// widgets stay out of the recording without changing any setting.
//
// Neither window is on layer 0, so spikot-wm does not manage them. Both ignore the mouse and the
// key display is a nonactivating panel, so neither takes focus from the window being moved.

import AppKit

let hold: TimeInterval = 2.6
let capFont = NSFont.systemFont(ofSize: 52, weight: .semibold)
let captionFont = NSFont.monospacedSystemFont(ofSize: 26, weight: .regular)

/// Modifier names the config accepts, as the glyph macOS menus print, in menu order.
let modifiers: [(names: Set<String>, glyph: String)] = [
    (["ctrl", "control"], "⌃"),
    (["alt", "opt", "option"], "⌥"),
    (["shift"], "⇧"),
    (["cmd", "command"], "⌘"),
]
let keyGlyphs = [
    "up": "↑", "down": "↓", "left": "←", "right": "→", "return": "↩", "escape": "⎋",
    "tab": "⇥", "space": "Space", "delete": "⌫",
]

/// `cmd-shift-3` as `["⇧", "⌘", "3"]`, and `down return` as `["↓", "↩"]`.
func caps(_ keys: String) -> [String] {
    keys.split(separator: " ").flatMap { capsOfOne(String($0)) }
}

func capsOfOne(_ hotkey: String) -> [String] {
    let parts = hotkey.lowercased().split(whereSeparator: { $0 == "-" || $0 == "+" }).map(String.init)
    guard let key = parts.last else { return [] }
    let held = modifiers.filter { !$0.names.isDisjoint(with: parts.dropLast()) }.map(\.glyph)
    return held + [keyGlyphs[key] ?? key.uppercased()]
}

func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = font
    field.textColor = color
    field.alignment = .center
    return field
}

func keyCap(_ glyph: String) -> NSView {
    let text = label(glyph, font: capFont, color: .white)
    let cap = NSView()
    cap.wantsLayer = true
    cap.layer?.backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor
    cap.layer?.borderColor = NSColor(white: 1, alpha: 0.35).cgColor
    cap.layer?.borderWidth = 2
    cap.layer?.cornerRadius = 14
    text.translatesAutoresizingMaskIntoConstraints = false
    cap.addSubview(text)
    NSLayoutConstraint.activate([
        text.centerXAnchor.constraint(equalTo: cap.centerXAnchor),
        text.centerYAnchor.constraint(equalTo: cap.centerYAnchor),
        cap.widthAnchor.constraint(greaterThanOrEqualTo: text.widthAnchor, constant: 40),
        cap.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        cap.heightAnchor.constraint(equalToConstant: 80),
    ])
    return cap
}

final class Display {
    let panel: NSPanel
    var generation = 0

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    func show(hotkey: String, caption: String) {
        let row = NSStackView(views: caps(hotkey).map(keyCap))
        row.spacing = 14
        let column = NSStackView(views: [row, label(caption, font: captionFont, color: .white)])
        column.orientation = .vertical
        column.spacing = 18
        if hotkey.isEmpty { row.isHidden = true }

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.86).cgColor
        box.layer?.cornerRadius = 26
        column.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 44),
            column.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -44),
            column.topAnchor.constraint(equalTo: box.topAnchor, constant: 30),
            column.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -30),
        ])
        panel.contentView = box
        let size = box.fittingSize

        guard let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        panel.setFrame(
            NSRect(x: area.midX - size.width / 2, y: area.minY + 90, width: size.width, height: size.height),
            display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        generation += 1
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.hide()
        }
    }

    func hide() {
        generation += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }
    }
}

/// One borderless window per display, filled with a dark gradient.
func backdrops() -> [NSWindow] {
    NSScreen.screens.map { screen in
        let window = NSWindow(
            contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.normalWindow)) - 1)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(srgbRed: 0.16, green: 0.20, blue: 0.27, alpha: 1).cgColor,
            NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1).cgColor,
        ]
        view.layer = gradient
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let display = Display()
let backdrop = backdrops()

Thread {
    while let line = readLine() {
        let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        DispatchQueue.main.async {
            if line == "clear" {
                display.hide()
            } else {
                display.show(
                    hotkey: String(fields[0]), caption: fields.count > 1 ? String(fields[1]) : "")
            }
        }
    }
    DispatchQueue.main.async { exit(0) }
}.start()

app.run()
