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
