import Carbon.HIToolbox
import Foundation
import Testing

@testable import StateCore

@Suite("Hotkey specs")
struct HotkeySpecTests {

    @Test("The modifier bits are Carbon's own")
    func modifierValues() {
        // StateCore spells these out rather than importing Carbon, so this is what keeps the
        // two from drifting. A wrong bit here would register a working hotkey on the wrong
        // modifier, which is indistinguishable from the key not firing.
        #expect(HotkeyModifier.command.rawValue == UInt32(cmdKey))
        #expect(HotkeyModifier.shift.rawValue == UInt32(shiftKey))
        #expect(HotkeyModifier.option.rawValue == UInt32(optionKey))
        #expect(HotkeyModifier.control.rawValue == UInt32(controlKey))
    }

    /// Every name in `HotkeySpec.keyCodes`, against the `kVK_*` constant it claims to be.
    ///
    /// Written out rather than derived because there is no way to enumerate the Carbon
    /// constants; typing them twice is the point, since a transposed digit binds a
    /// neighbouring key and nothing else would notice.
    static let carbonKeyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "s": kVK_ANSI_S, "d": kVK_ANSI_D, "f": kVK_ANSI_F,
        "h": kVK_ANSI_H, "g": kVK_ANSI_G, "z": kVK_ANSI_Z, "x": kVK_ANSI_X,
        "c": kVK_ANSI_C, "v": kVK_ANSI_V, "b": kVK_ANSI_B, "q": kVK_ANSI_Q,
        "w": kVK_ANSI_W, "e": kVK_ANSI_E, "r": kVK_ANSI_R, "y": kVK_ANSI_Y,
        "t": kVK_ANSI_T, "o": kVK_ANSI_O, "u": kVK_ANSI_U, "i": kVK_ANSI_I,
        "p": kVK_ANSI_P, "l": kVK_ANSI_L, "j": kVK_ANSI_J, "k": kVK_ANSI_K,
        "n": kVK_ANSI_N, "m": kVK_ANSI_M,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "equal": kVK_ANSI_Equal, "minus": kVK_ANSI_Minus, "grave": kVK_ANSI_Grave,
        "leftbracket": kVK_ANSI_LeftBracket, "rightbracket": kVK_ANSI_RightBracket,
        "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
        "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period, "slash": kVK_ANSI_Slash,
        "backslash": kVK_ANSI_Backslash,
        "return": kVK_Return, "tab": kVK_Tab, "space": kVK_Space,
        "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete, "escape": kVK_Escape,
        "help": kVK_Help, "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
        "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14,
        "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18,
        "f19": kVK_F19, "f20": kVK_F20,
    ]

    @Test("Every key code matches the Carbon constant it names")
    func keyCodesMatchCarbon() {
        for (name, code) in Self.carbonKeyCodes {
            #expect(HotkeySpec.keyCodes[name] == UInt32(code), "\(name) has the wrong code")
        }
        #expect(
            HotkeySpec.keyCodes.count == Self.carbonKeyCodes.count,
            "a key was added to the table without being checked against Carbon")
    }

    @Test("A plain binding parses")
    func simple() throws {
        let spec = try HotkeySpec.parse("alt-h")
        #expect(spec.keyCode == UInt32(kVK_ANSI_H))
        #expect(spec.modifiers == UInt32(optionKey))
        #expect(spec.canonical == "alt-h")
    }

    @Test("Modifiers combine, and the canonical form puts them in a fixed order")
    func combined() throws {
        let spec = try HotkeySpec.parse("cmd-shift-1")
        #expect(spec.modifiers == UInt32(cmdKey) | UInt32(shiftKey))
        #expect(spec.canonical == "shift-cmd-1")
        // Order written does not matter; the canonical form is what identifies the binding.
        #expect(try HotkeySpec.parse("shift-cmd-1").canonical == spec.canonical)
    }

    @Test("An skhdrc line parses unchanged, spaces and plus signs included")
    func skhdSyntax() throws {
        // Lifted from ~/.config/skhd/skhdrc, which is the point: a binding moved over does
        // not have to be rewritten.
        let spec = try HotkeySpec.parse("cmd + shift - e")
        #expect(spec.keyCode == UInt32(kVK_ANSI_E))
        #expect(spec.modifiers == UInt32(cmdKey) | UInt32(shiftKey))
    }

    @Test("Case and aliases are accepted")
    func aliases() throws {
        #expect(try HotkeySpec.parse("CMD-Shift-RETURN").keyCode == UInt32(kVK_Return))
        #expect(try HotkeySpec.parse("ctrl-opt-esc").keyCode == UInt32(kVK_Escape))
        #expect(try HotkeySpec.parse("ctrl-option-enter").keyCode == UInt32(kVK_Return))
        #expect(try HotkeySpec.parse("cmd-alt-pgup").keyCode == UInt32(kVK_PageUp))
        // Arrow names both ways, since Rectangle's UI writes them as arrows.
        #expect(try HotkeySpec.parse("cmd-shift-uparrow").keyCode == UInt32(kVK_UpArrow))
        #expect(try HotkeySpec.parse("cmd-shift-up").keyCode == UInt32(kVK_UpArrow))
    }

    @Test("A key with no modifier is refused")
    func bareKey() {
        // Registering this would swallow every press of that key in every application.
        #expect(throws: HotkeyError.bareKey("h")) { try HotkeySpec.parse("h") }
    }

    @Test("A misspelled modifier and a missing key are different errors")
    func badModifiers() {
        #expect(throws: HotkeyError.unknownModifier("meta")) { try HotkeySpec.parse("meta-h") }
        #expect(throws: HotkeyError.noKey("cmd-alt")) { try HotkeySpec.parse("cmd-alt") }
        #expect(throws: HotkeyError.empty) { try HotkeySpec.parse("  ") }
    }

    @Test("fn is rejected with its own message, since it cannot be matched at all")
    func functionModifier() {
        // RegisterEventHotKey takes the four Carbon modifier bits; fn is not one of them.
        #expect(throws: HotkeyError.functionModifier("fn-f1")) { try HotkeySpec.parse("fn-f1") }
    }

    @Test("An unknown key name says which token was not understood")
    func unknownKey() throws {
        #expect(throws: HotkeyError.unknownKey("volumeup")) {
            try HotkeySpec.parse("cmd-volumeup")
        }
        // The literal '-' cannot be written, because '-' separates. The alias is the way in.
        #expect(throws: HotkeyError.noKey("cmd--")) { try HotkeySpec.parse("cmd--") }
        #expect(try HotkeySpec.parse("cmd-minus").keyCode == UInt32(kVK_ANSI_Minus))
    }
}

@Suite("Hotkey commands")
struct HotkeyCommandTests {

    @Test("A bare argument lands on the command's positional slot")
    func positional() throws {
        let request = try HotkeyCommand.request(from: "focus left")
        #expect(request.cmd == "focus")
        #expect(request.args == ["target": "left"])
    }

    @Test("A command with no argument yields empty args")
    func noArguments() throws {
        #expect(try HotkeyCommand.request(from: "state").args.isEmpty)
        #expect(try HotkeyCommand.request(from: "reload").cmd == "reload")
    }

    @Test("Flags and name=value both work, so new commands need no parser change")
    func explicitArguments() throws {
        #expect(try HotkeyCommand.request(from: "focus --window 42").args == ["window": "42"])
        #expect(try HotkeyCommand.request(from: "focus pid=5") .args == ["pid": "5"])
        #expect(try HotkeyCommand.request(from: "list -f json").cmd == "list")
    }

    @Test("Extra whitespace does not change the parse")
    func whitespace() throws {
        #expect(try HotkeyCommand.request(from: "  focus   right  ").args == ["target": "right"])
    }

    @Test("A command the agent does not answer is refused when written, not when pressed")
    func unknownCommand() {
        // This is what lets the menu bar show a binding as broken before anyone presses it,
        // and what will reject a `place` binding until spikot-win-80o.2 implements it.
        #expect(throws: HotkeyError.unknownCommand("place", known: IPC.commands.sorted())) {
            try HotkeyCommand.request(from: "place 1")
        }
        #expect(throws: HotkeyError.emptyCommand("alt-h")) {
            try HotkeyCommand.request(from: "   ", key: "alt-h")
        }
    }

    @Test("A bare argument for a command that takes none is reported")
    func unexpectedArgument() {
        #expect(throws: HotkeyError.unexpectedArgument(command: "reload", token: "now")) {
            try HotkeyCommand.request(from: "reload now")
        }
    }

    @Test("A flag with nothing after it is reported")
    func danglingFlag() {
        #expect(throws: HotkeyError.danglingFlag("window")) {
            try HotkeyCommand.request(from: "focus --window")
        }
    }

    @Test("Every command in the vocabulary parses on its own")
    func vocabularyParses() throws {
        // Guards against a name being added to IPC.commands that the parser then rejects.
        for command in IPC.commands {
            #expect(try HotkeyCommand.request(from: command).cmd == command)
        }
    }
}
