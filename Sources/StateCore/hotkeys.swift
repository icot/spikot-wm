import Foundation

/// A hotkey in the form Carbon's `RegisterEventHotKey` wants it: a virtual key code plus a
/// modifier mask.
///
/// Parsed here rather than in the agent so it can be tested without a run loop, and so the
/// CLI can validate a config file it will never register.
public struct HotkeySpec: Hashable, Sendable {
    /// Virtual key code, e.g. 4 for the key labelled H on an ANSI layout.
    public let keyCode: UInt32
    /// Carbon modifier mask: the OR of `HotkeyModifier` raw values.
    public let modifiers: UInt32
    /// Normalised spelling, `ctrl-alt-shift-cmd-key`, for display and for comparing two
    /// specs written differently.
    public let canonical: String

    public init(keyCode: UInt32, modifiers: UInt32, canonical: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.canonical = canonical
    }
}

/// The four modifiers `RegisterEventHotKey` accepts, with Carbon's own bit values.
///
/// Spelled out rather than imported from Carbon so this file stays free of it; the values
/// are asserted against `cmdKey`, `shiftKey`, `optionKey` and `controlKey` in the tests.
public enum HotkeyModifier: UInt32, CaseIterable, Sendable {
    case command = 0x0100
    case shift = 0x0200
    case option = 0x0800
    case control = 0x1000

    /// Accepted spellings. `alt` and `opt` are the same key; skhd and Rectangle disagree on
    /// which to write, and the user's skhdrc uses `alt`.
    static let names: [String: HotkeyModifier] = [
        "cmd": .command, "command": .command,
        "shift": .shift,
        "alt": .option, "opt": .option, "option": .option,
        "ctrl": .control, "control": .control,
    ]

    /// Display order, which is also the order modifiers are printed on menu items.
    static let displayOrder: [(HotkeyModifier, String)] = [
        (.control, "ctrl"), (.option, "alt"), (.shift, "shift"), (.command, "cmd"),
    ]
}

/// Why a hotkey string could not be turned into a `HotkeySpec`.
///
/// Every case names the offending token, because these surface one per binding in the menu
/// bar and in the log, where "invalid hotkey" on its own would be useless.
public enum HotkeyError: Error, CustomStringConvertible, Equatable {
    case empty
    case noKey(String)
    case unknownModifier(String)
    case unknownKey(String)
    case bareKey(String)
    case functionModifier(String)
    case emptyCommand(String)
    case unknownCommand(String, known: [String])
    case unexpectedArgument(command: String, token: String)
    case danglingFlag(String)

    public var description: String {
        switch self {
        case .empty:
            return "empty hotkey"
        case .noKey(let raw):
            return "'\(raw)' names modifiers but no key"
        case .unknownModifier(let token):
            return "unknown modifier '\(token)'; expected cmd, alt, ctrl or shift"
        case .unknownKey(let token):
            return "unknown key '\(token)'; see HotkeySpec.keyCodes for the accepted names"
        case .bareKey(let raw):
            return "'\(raw)' has no modifier, which would grab that key from every"
                + " application; add at least one of cmd, alt, ctrl or shift"
        case .functionModifier(let raw):
            return "'\(raw)' uses fn, which RegisterEventHotKey cannot match"
        case .emptyCommand(let key):
            return "'\(key)' is bound to an empty command"
        case .unknownCommand(let cmd, let known):
            return "no command '\(cmd)'; the agent answers \(known.joined(separator: ", "))"
        case .unexpectedArgument(let command, let token):
            return "'\(command)' takes no bare argument, so '\(token)' has nowhere to go;"
                + " write it as name=value"
        case .danglingFlag(let flag):
            return "--\(flag) has no value"
        }
    }
}

extension HotkeySpec {
    /// Virtual key codes, by the name written in the config file.
    ///
    /// These are `kVK_*` from Carbon's Events.h. They identify a physical key position, not
    /// a character: on a non-ANSI layout the key named `h` here is the one labelled H on a
    /// US keyboard, wherever that layout puts it. skhd behaves the same way, so bindings
    /// carried over from `skhdrc` land on the same keys.
    public static let keyCodes: [String: UInt32] = [
        // Letters, in kVK_ANSI_* order rather than alphabetical, which is how Events.h
        // lists them and how the numbers make sense.
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "equal": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29,
        "rightbracket": 30, "o": 31, "u": 32, "leftbracket": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "quote": 39, "k": 40, "semicolon": 41,
        "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
        "tab": 48, "space": 49, "grave": 50, "delete": 51, "escape": 53,
        // Function and navigation keys.
        "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101, "f11": 103,
        "f13": 105, "f16": 106, "f14": 107, "f10": 109, "f12": 111, "f15": 113,
        "help": 114, "home": 115, "pageup": 116, "forwarddelete": 117, "f4": 118,
        "end": 119, "f2": 120, "pagedown": 121, "f1": 122,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    /// Alternative spellings, so a binding copied from skhd or from a Rectangle screenshot
    /// does not have to be translated by hand.
    static let keyAliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete", "del": "forwarddelete",
        "hyphen": "minus", "dash": "minus", "plus": "equal",
        "leftarrow": "left", "rightarrow": "right", "uparrow": "up", "downarrow": "down",
        "pgup": "pageup", "pgdn": "pagedown", "pagedn": "pagedown",
        "`": "grave", "-": "minus", "=": "equal", "[": "leftbracket", "]": "rightbracket",
        ";": "semicolon", "'": "quote", ",": "comma", ".": "period", "/": "slash",
        "\\": "backslash",
    ]

    /// Parses `cmd-shift-1`, `alt - h` or `ctrl+opt+delete` into a spec.
    ///
    /// Both `-` and `+` separate, and whitespace around them is ignored, so a line lifted
    /// from `skhdrc` (`cmd + shift - e`) parses unchanged. The `-` key itself is therefore
    /// unreachable as a literal and is written `minus`.
    public static func parse(_ raw: String) throws -> HotkeySpec {
        let tokens = raw
            .split(whereSeparator: { $0 == "-" || $0 == "+" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { throw HotkeyError.empty }

        var mask: UInt32 = 0
        for token in tokens.dropLast() {
            if token == "fn" { throw HotkeyError.functionModifier(raw) }
            guard let modifier = HotkeyModifier.names[token] else {
                throw HotkeyError.unknownModifier(token)
            }
            mask |= modifier.rawValue
        }

        guard let last = tokens.last else { throw HotkeyError.noKey(raw) }
        // A trailing modifier name means the key is missing rather than misspelled, which
        // is a different mistake and deserves a different message.
        if HotkeyModifier.names[last] != nil { throw HotkeyError.noKey(raw) }
        let name = keyAliases[last] ?? last
        guard let keyCode = keyCodes[name] else { throw HotkeyError.unknownKey(last) }
        // No modifier means every press of that key anywhere would be swallowed.
        guard mask != 0 else { throw HotkeyError.bareKey(raw) }

        let prefix = HotkeyModifier.displayOrder
            .filter { mask & $0.0.rawValue != 0 }
            .map(\.1)
        return HotkeySpec(
            keyCode: keyCode, modifiers: mask,
            canonical: (prefix + [name]).joined(separator: "-"))
    }
}

/// Turns the command half of a binding — `"focus left"` — into the `Request` the agent
/// already answers.
///
/// A binding is literally an IPC request, so hotkeys inherit the whole command vocabulary
/// and need no dispatch table of their own.
public enum HotkeyCommand {
    /// Where a single bare argument goes, per command. `focus left` means
    /// `args["target"] = "left"`.
    ///
    /// A command absent from this table takes no bare argument; anything else has to be
    /// written `name=value`.
    static let positionalArgument: [String: String] = [
        "focus": "target",
        "list": "format",
        "place": "action",
    ]

    /// Parses a command line into a request, rejecting commands the agent does not answer.
    ///
    /// Rejecting here rather than on the keypress is what lets the menu bar show a binding
    /// as broken before anyone presses it.
    public static func request(from command: String, key: String = "") throws -> Request {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let cmd = tokens.first else { throw HotkeyError.emptyCommand(key) }
        guard IPC.commands.contains(cmd) else {
            throw HotkeyError.unknownCommand(cmd, known: IPC.commands.sorted())
        }

        // exec keeps its tail verbatim: it is an argument vector for another program, not
        // flags for this one, so `--args` and `-e` below it must not be read as ours.
        if cmd == "exec" {
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            let line = trimmed.dropFirst(cmd.count).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { throw HotkeyError.emptyCommand(key) }
            // Tokenised now as well as at run time, so an unbalanced quote is reported when
            // the binding is registered rather than on the keypress.
            _ = try ExecCommand.tokenize(line)
            return Request(cmd: cmd, args: ["command": line])
        }

        var args: [String: String] = [:]
        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("--") {
                let name = String(token.dropFirst(2))
                guard index + 1 < tokens.count else { throw HotkeyError.danglingFlag(name) }
                args[name] = tokens[index + 1]
                index += 2
            } else if let split = token.firstIndex(of: "="), split != token.startIndex {
                args[String(token[token.startIndex..<split])] =
                    String(token[token.index(after: split)...])
                index += 1
            } else {
                guard let name = positionalArgument[cmd] else {
                    throw HotkeyError.unexpectedArgument(command: cmd, token: token)
                }
                args[name] = token
                index += 1
            }
        }
        return Request(cmd: cmd, args: args)
    }
}
