import Foundation
import Testing

@testable import StateCore

@Suite("Exec command lines")
struct ExecCommandTests {

    @Test("A plain command line splits into argv")
    func simple() throws {
        #expect(try ExecCommand.tokenize("emacsclient -c -n") == ["emacsclient", "-c", "-n"])
    }

    @Test("Runs of whitespace separate once, and tabs count")
    func whitespace() throws {
        #expect(try ExecCommand.tokenize("  open \t -n  /Applications/Ghostty.app ")
            == ["open", "-n", "/Applications/Ghostty.app"])
    }

    @Test("Quotes group, and an empty pair is still an argument")
    func quoting() throws {
        // `emacsclient -c -n -a ""` is the mylauncher invocation, and the empty argument is
        // what stops emacsclient starting an alternate editor.
        #expect(try ExecCommand.tokenize(#"emacsclient -c -n -a """# ) == ["emacsclient", "-c", "-n", "-a", ""])
        #expect(try ExecCommand.tokenize(#"say "hello there""#) == ["say", "hello there"])
        #expect(try ExecCommand.tokenize("say 'hello there'") == ["say", "hello there"])
        // Inside one quote the other is literal, which is how an apostrophe is written.
        #expect(try ExecCommand.tokenize(#"say "it's here""#) == ["say", "it's here"])
    }

    @Test("An unterminated quote is an error rather than a silently truncated argument")
    func unterminated() {
        #expect(throws: ExecError.unterminatedQuote(#"say "hello"#)) {
            try ExecCommand.tokenize(#"say "hello"#)
        }
    }

    @Test("An empty line is an error")
    func empty() {
        #expect(throws: ExecError.empty) { try ExecCommand.tokenize("   ") }
    }

    @Test("A leading tilde expands, and one anywhere else does not")
    func tilde() {
        let home = NSHomeDirectory()
        #expect(ExecCommand.expandingTilde("~/.local/bin") == home + "/.local/bin")
        #expect(ExecCommand.expandingTilde("~") == home)
        #expect(ExecCommand.expandingTilde("/opt/~/bin") == "/opt/~/bin", "only a leading tilde")
    }

    @Test("A name with a slash is used as a path")
    func pathGiven() throws {
        #expect(try ExecCommand.resolve("/bin/sh", searchPath: []).path == "/bin/sh")
    }

    @Test("A path that is not executable is reported as such, not as missing")
    func notExecutable() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-exec-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a program".utf8).write(to: url)
        #expect(throws: ExecError.notExecutable(url.path)) {
            try ExecCommand.resolve(url.path, searchPath: [])
        }
    }

    @Test("A bare name is found in the search path, in order")
    func searchPathOrder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-exec-\(UUID().uuidString)")
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Only the second directory has it, so the first must be skipped rather than ending
        // the search.
        let script = second.appendingPathComponent("mylauncher")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let found = try ExecCommand.resolve(
            "mylauncher", searchPath: [first.path, second.path])
        #expect(found.path == script.path)
    }

    @Test("A missing command names the search path it was looked for in")
    func notFound() {
        // The message is what appears in the menu bar against the binding, so it has to say
        // where to put the command or what to add to execPath.
        #expect(throws: ExecError.notFound("choosewindow", searchPath: ["/usr/bin"])) {
            try ExecCommand.resolve("choosewindow", searchPath: ["/usr/bin"])
        }
        let message = ExecError.notFound("choosewindow", searchPath: ["/usr/bin"]).description
        #expect(message.contains("execPath"))
    }

    @Test("The child's PATH is the search path with tildes expanded")
    func pathVariable() {
        let value = ExecCommand.pathVariable(["~/.local/bin", "/usr/bin"])
        #expect(value == NSHomeDirectory() + "/.local/bin:/usr/bin")
        #expect(!value.contains("~"), "a literal tilde in PATH would not resolve for the child")
    }

    @Test("The default search path covers where the user's own tools live")
    func defaultSearchPath() {
        // mylauncher is in ~/.local/bin and calls spikot-wm, rg and choose by bare name, and
        // emacsclient is in /opt/homebrew/bin. A LaunchAgent's PATH has neither.
        #expect(Config.defaultExecPath.contains("~/.local/bin"))
        #expect(Config.defaultExecPath.contains("/opt/homebrew/bin"))
        #expect(Config.standard.execPath == Config.defaultExecPath)
    }
}

@Suite("Exec bindings")
struct ExecBindingTests {

    @Test("exec is part of the vocabulary, so a binding can name it")
    func inVocabulary() {
        #expect(IPC.commands.contains("exec"))
    }

    @Test("The command line is kept verbatim, flags and all")
    func verbatim() throws {
        // The trap this avoids: --args and -e belong to `open`, not to spikot-wm, so the
        // generic flag parsing must not touch them.
        let line = "open /Applications/Ghostty.app -n --args -e ~/.local/bin/choosepass fzf"
        let request = try HotkeyCommand.request(from: "exec " + line)
        #expect(request.cmd == "exec")
        #expect(request.args == ["command": line])
    }

    @Test("A quoted argument survives the round trip to argv")
    func quotedRoundTrip() throws {
        let request = try HotkeyCommand.request(from: #"exec emacsclient -c -n -a """#)
        let argv = try ExecCommand.tokenize(request.args["command"] ?? "")
        #expect(argv == ["emacsclient", "-c", "-n", "-a", ""])
    }

    @Test("exec with nothing to run is refused")
    func needsACommand() {
        #expect(throws: HotkeyError.emptyCommand("cmd-shift-e")) {
            try HotkeyCommand.request(from: "exec   ", key: "cmd-shift-e")
        }
    }

    @Test("An unbalanced quote is caught when the binding is written, not on the keypress")
    func quoteCheckedEarly() {
        #expect(throws: ExecError.unterminatedQuote(#"say "hello"#)) {
            try HotkeyCommand.request(from: #"exec say "hello"#)
        }
    }
}

@Suite("Launching applications")
struct LaunchPlanTests {

    @Test("A config command wins over everything, which is what Emacs needs")
    func commandFirst() {
        // emacsclient against the running daemon rather than a second Emacs, and there is no
        // /Applications/Emacs.app on this machine anyway.
        let plan = LaunchPlan.resolve("Emacs", config: Config.standard, bundleURL: { _ in nil })
        #expect(plan == .command(["emacsclient", "-c", "-n", "-a", ""]))
    }

    @Test("A bundle identifier is used when there is no command")
    func bundleIdentifier() {
        let url = URL(fileURLWithPath: "/Applications/Firefox.app")
        let plan = LaunchPlan.resolve(
            "Firefox", config: Config.standard,
            bundleURL: { $0 == "org.mozilla.firefox" ? url : nil })
        #expect(plan == .bundle(url))
    }

    @Test("The application name is matched without regard to case")
    func caseInsensitive() {
        let plan = LaunchPlan.resolve("emacs", config: Config.standard, bundleURL: { _ in nil })
        #expect(plan == .command(["emacsclient", "-c", "-n", "-a", ""]))
    }

    @Test("With no config entry it looks for a bundle named after the application")
    func nameFallback() {
        // The old script's generic fallback read a ~/.apps-cache that does not exist and only
        // echoed what it found, so nothing outside its four applications ever launched.
        let config = Config(launch: [:])
        let plan = LaunchPlan.resolve(
            "Hammerspoon", config: config, bundleURL: { _ in nil })
        #expect(plan == .bundle(URL(fileURLWithPath: "/Applications/Hammerspoon.app")))
    }

    @Test("A missing application says where it looked")
    func notFound() {
        let config = Config(launch: [:])
        guard case .notFound(let searched) = LaunchPlan.resolve(
            "NoSuchApplication", config: config, bundleURL: { _ in nil })
        else {
            #expect(Bool(false), "expected notFound")
            return
        }
        #expect(searched.contains("/Applications/NoSuchApplication.app"))
        #expect(searched.contains { $0.contains("/Applications/NoSuchApplication.app") })
        let message = LaunchError.noApplication("NoSuchApplication", searched: searched).description
        #expect(message.contains("launch section"))
    }

    @Test("A config entry with a bundle id that resolves to nothing falls through to the name")
    func bundleMissingFallsThrough() {
        let config = Config(launch: ["Ghostty": LaunchApp(bundleID: "com.example.gone")])
        let plan = LaunchPlan.resolve("Ghostty", config: config, bundleURL: { _ in nil })
        #expect(plan == .bundle(URL(fileURLWithPath: "/Applications/Ghostty.app")))
    }

    @Test("The search path covers the user's own Applications folder, with the tilde expanded")
    func searchDirectories() {
        #expect(LaunchPlan.searchDirectories.contains("~/Applications"))
        let config = Config(launch: [:])
        guard case .notFound(let searched) = LaunchPlan.resolve(
            "Nothing", config: config, bundleURL: { _ in nil })
        else { return }
        #expect(!searched.contains { $0.hasPrefix("~") }, "a literal tilde would never match")
        #expect(searched.contains { $0.hasPrefix(NSHomeDirectory()) })
    }

    @Test("Missing launch defaults can be added, as with the hotkeys")
    func addMissingDefaults() {
        var config = Config(launch: [:])
        #expect(config.missingDefaultLaunch.count == Config.defaultLaunch.count)
        config.addMissingDefaultLaunch()
        #expect(config.launch == Config.defaultLaunch)
        // An entry the user has changed is left alone.
        var edited = Config(launch: ["Firefox": LaunchApp(bundleID: "org.mozilla.firefoxdeveloperedition")])
        edited.addMissingDefaultLaunch()
        #expect(edited.launch["Firefox"]?.bundleID == "org.mozilla.firefoxdeveloperedition")
        #expect(edited.launch["Emacs"]?.command != nil)
    }
}

@Suite("Finding an application's windows")
struct LaunchMatchingTests {

    private func state(_ owners: [String]) -> State {
        let windows = owners.enumerated().map { index, owner in
            Fixtures.window(number: index + 1, owner: owner, coordX: 0, width: 400)
        }
        let state = Fixtures.state(windows: windows, displays: Fixtures.laptopOnly)
        state.initialize()
        return state
    }

    @Test("An exact name match beats a substring")
    func exactWins() {
        // The old script piped the whole listing through rg, so a window title containing the
        // name counted as a window of that application.
        let state = self.state(["Safari", "Safari Technology Preview"])
        let found = state.windows(ofApplication: "Safari")
        #expect(found.map(\.kCGWindowOwnerName) == ["Safari"])
    }

    @Test("A prefix is enough when nothing matches exactly")
    func prefix() {
        let state = self.state(["Firefox", "Emacs"])
        #expect(state.windows(ofApplication: "fire").map(\.kCGWindowNumber) == [1])
    }

    @Test("A substring is the last resort")
    func substring() {
        let state = self.state(["Google Chrome", "Emacs"])
        #expect(state.windows(ofApplication: "chrome").map(\.kCGWindowNumber) == [1])
    }

    @Test("Every window of one application is returned, in window-server order")
    func several() {
        let state = self.state(["Firefox", "Emacs", "Firefox"])
        #expect(state.windows(ofApplication: "Firefox").map(\.kCGWindowNumber) == [1, 3])
    }

    @Test("An application with no windows returns nothing, which is what triggers a launch")
    func none() {
        #expect(self.state(["Emacs"]).windows(ofApplication: "Firefox").isEmpty)
    }

    @Test("The outcome summaries say what happened")
    func summaries() {
        #expect(LaunchOutcome.launched("Firefox").summary == "launched Firefox")
        #expect(LaunchOutcome.focused(window: 7, owner: "Emacs").summary == "focused Emacs 7")
        #expect(
            LaunchOutcome.several(window: 7, owner: "Firefox", count: 3).summary
                == "focused Firefox 7, the first of 3 windows")
    }
}

@Suite("Picker list")
struct PickerModelTests {
    private let rows = [
        PickerModel.Row(window: 1, label: "Firefox — EL PAÍS"),
        PickerModel.Row(window: 2, label: "Firefox — GitHub"),
        PickerModel.Row(window: 3, label: "Emacs — AGENTS.md"),
    ]

    @Test("Everything is shown until something is typed")
    func unfiltered() {
        let model = PickerModel(rows: rows)
        #expect(model.matches.count == 3)
        #expect(model.selected?.window == 1)
    }

    @Test("Typing filters on the whole line, so a title narrows as well as an application")
    func filtering() {
        var model = PickerModel(rows: rows)
        model.type("git")
        #expect(model.matches.map(\.window) == [2], "matched on the title")
        model.backspace()
        model.backspace()
        model.backspace()
        model.type("emacs")
        #expect(model.matches.map(\.window) == [3], "and on the application, without regard to case")
    }

    @Test("A filter that matches nothing leaves nothing selected rather than a stale row")
    func noMatches() {
        var model = PickerModel(rows: rows)
        model.type("nothing here")
        #expect(model.matches.isEmpty)
        #expect(model.selected == nil)
    }

    @Test("The selection stays inside the list as it shrinks")
    func selectionClamped() {
        var model = PickerModel(rows: rows)
        model.move(by: 2)
        #expect(model.selected?.window == 3)
        model.type("Firefox")
        #expect(model.matches.count == 2)
        #expect(model.selected?.window == 2, "clamped to the last match, not left past the end")
    }

    @Test("Moving wraps at both ends")
    func wrapping() {
        var model = PickerModel(rows: rows)
        model.move(by: -1)
        #expect(model.selected?.window == 3, "up from the first row reaches the last")
        model.move(by: 1)
        #expect(model.selected?.window == 1)
        model.move(by: 5)
        #expect(model.selected?.window == 3, "an offset larger than the list still lands in it")
    }

    @Test("Number keys pick by position in the filtered list")
    func numberKeys() {
        var model = PickerModel(rows: rows)
        #expect(model.row(forNumberKey: 1)?.window == 1)
        #expect(model.row(forNumberKey: 3)?.window == 3)
        #expect(model.row(forNumberKey: 4) == nil, "past the end is nothing, not a wrap")
        model.type("Firefox")
        #expect(model.row(forNumberKey: 2)?.window == 2)
        #expect(model.row(forNumberKey: 3) == nil, "the numbers follow the filter")
    }

    @Test("Backspacing past the start is harmless")
    func emptyBackspace() {
        var model = PickerModel(rows: rows)
        model.backspace()
        #expect(model.filter.isEmpty)
        #expect(model.matches.count == 3)
    }

    @Test("An empty list has nothing to select and nothing to move")
    func empty() {
        var model = PickerModel(rows: [])
        model.move(by: 1)
        #expect(model.selected == nil)
        #expect(model.row(forNumberKey: 1) == nil)
    }
}
