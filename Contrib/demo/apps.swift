// Hides the running applications before a demo recording and puts them back afterwards.
//
//   apps hide <state file> [pid...]
//                            hide every visible application but those, adding their pids to the
//                            file
//   apps show <state file>   unhide exactly those, then delete the file
//   apps crop                the main display below the menu bar, as screencapture -R wants it
//   apps keys <key>...       post keystrokes: return, escape, up, down, ... or literal text
//
// `NSRunningApplication.hide()` returns false even when it works, because hiding is
// asynchronous, so the state file is written from what was visible beforehand rather than
// from its return value.

import AppKit

func usage() -> Never {
    FileHandle.standardError.write(
        Data("usage: apps hide <state file> [pid...] | apps show <state file> | apps crop | apps keys <key>...\n".utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 2 else { usage() }

switch args[1] {
case "hide":
    guard args.count >= 3 else { usage() }
    // Adds to the file rather than replacing it. Hiding the active application makes macOS
    // activate another, which unhides that one, so record.sh calls this until nothing is left
    // on screen, and each call has to keep the pids the earlier ones hid.
    //
    // Finder is never hidden: it is what macOS activates when everything else is, so hiding it
    // too makes macOS activate, and unhide, some other application, round and round. A Finder
    // window left open is caught by record.sh's check for windows that are not the demo's.
    let keep = Set(args.dropFirst(3).compactMap { pid_t($0) })
    let visible = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular && !$0.isHidden && !keep.contains($0.processIdentifier)
            && $0.bundleIdentifier != "com.apple.finder"
    }
    let earlier = (try? String(contentsOfFile: args[2], encoding: .utf8))?.split(separator: "\n")
        .map(String.init) ?? []
    let pids = Set(earlier + visible.map { String($0.processIdentifier) })
    try pids.sorted().joined(separator: "\n").write(toFile: args[2], atomically: true, encoding: .utf8)
    visible.forEach { _ = $0.hide() }
    print("hid \(visible.count)")

case "show":
    guard args.count == 3 else { usage() }
    let text = (try? String(contentsOfFile: args[2], encoding: .utf8)) ?? ""
    let pids = Set(text.split(separator: "\n").compactMap { pid_t($0) })
    for app in NSWorkspace.shared.runningApplications where pids.contains(app.processIdentifier) {
        _ = app.unhide()
    }
    try? FileManager.default.removeItem(atPath: args[2])
    print("unhid \(pids.count)")

case "keys":
    // Posts each argument as a keystroke: a key name from `named`, or else literal text typed
    // one character at a time. Posting needs Accessibility, so record.sh runs this through the
    // agent's `exec`, whose children borrow the agent's grant.
    let named: [String: CGKeyCode] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    let source = CGEventSource(stateID: .hidSystemState)
    func post(_ code: CGKeyCode, text: String? = nil) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            if let text {
                let units = Array(text.utf16)
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event?.post(tap: .cghidEventTap)
        }
        usleep(90_000)
    }
    for token in args.dropFirst(2) {
        if let code = named[token] {
            post(code)
        } else {
            token.forEach { post(0, text: String($0)) }
        }
    }

case "crop":
    // screencapture -R takes a top-left origin, so the menu bar is the strip at y = 0.
    guard let screen = NSScreen.screens.first else { exit(1) }
    let frame = screen.frame, visible = screen.visibleFrame
    let menuBar = Int(frame.maxY - visible.maxY)
    print("0,\(menuBar),\(Int(frame.width)),\(Int(frame.height) - menuBar)")

default:
    usage()
}
