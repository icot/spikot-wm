// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The command line of a `choose` binding: a command whose output lines fill the picker, and a
/// command run with the line picked.
///
/// Written `choose <list command> | <action command>`, for example
/// `choose choosepass list | pass show -c {}`. The `|` is not a shell pipe — the list's output goes
/// to the picker, and only the picked line reaches the action — but it reads in the same direction.
/// Each side is an `exec` command line, with the same quoting and the same search path.
///
/// It replaces `choose-gui` for the one script still using it, `choosepass`, which could not run
/// from a binding: started through `open -n Ghostty.app --args -e`, Ghostty gets launchd's `PATH`
/// rather than `execPath`, so `fzf`, `pass` and `gpg` were all missing in the terminal it opened.
public struct ChooseCommand: Equatable, Sendable {
    /// The argument vector whose standard output is the list.
    public let list: [String]
    /// The argument vector run with the picked line; see `action(for:)`.
    public let action: [String]

    /// The token in the action replaced by the picked line.
    public static let placeholder = "{}"

    public init(list: [String], action: [String]) {
        self.list = list
        self.action = action
    }

    /// Parses `<list command> | <action command>`.
    ///
    /// Only an unquoted `|` separates, so `'|'` is an ordinary argument on either side. A second
    /// unquoted `|` is an error rather than a literal, because it would read as a pipeline that
    /// is not one.
    public static func parse(_ line: String) throws -> ChooseCommand {
        var separators: [String.Index] = []
        var quote: Character?
        for index in line.indices {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "|" {
                separators.append(index)
            }
        }
        if quote != nil { throw ExecError.unterminatedQuote(line) }
        guard let separator = separators.first else { throw ChooseError.missingAction(line) }
        guard separators.count == 1 else { throw ChooseError.severalSeparators(line) }

        let listLine = String(line[..<separator])
        let actionLine = String(line[line.index(after: separator)...])
        guard !listLine.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ChooseError.missingList(line)
        }
        guard !actionLine.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ChooseError.missingAction(line)
        }
        return ChooseCommand(
            list: try ExecCommand.tokenize(listLine),
            action: try ExecCommand.tokenize(actionLine))
    }

    /// The action's argument vector for a picked line.
    ///
    /// Every `{}` in every argument is replaced, so `--entry={}` works as well as a bare `{}`.
    /// With no `{}` anywhere the line is appended as the last argument, which is what `xargs`
    /// does and what `pass show -c` wants anyway. argv[0] is never substituted: the picked line
    /// is data, and letting it name the program to run would make the list decide what executes.
    public func action(for line: String) -> [String] {
        let arguments = action.dropFirst()
        guard arguments.contains(where: { $0.contains(Self.placeholder) }) else {
            return action + [line]
        }
        return [action[0]]
            + arguments.map { $0.replacingOccurrences(of: Self.placeholder, with: line) }
    }

    /// The picker's rows from the list command's output: one per non-empty line, in order.
    ///
    /// Trailing whitespace is dropped, which takes the `\r` of a CRLF line with it; leading
    /// whitespace is kept, because it may be part of the value.
    public static func rows(fromOutput output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            var line = Substring(line)
            while let last = line.last, last.isWhitespace { line.removeLast() }
            return line.isEmpty ? nil : String(line)
        }
    }
}

/// Why a `choose` command line could not be understood.
public enum ChooseError: Error, CustomStringConvertible, Equatable {
    case missingList(String)
    case missingAction(String)
    case severalSeparators(String)

    public var description: String {
        switch self {
        case .missingList(let line):
            return "choose needs a command before '|' to list the choices, in '\(line)'"
        case .missingAction(let line):
            return "choose needs '<list command> | <action command>', in '\(line)'"
        case .severalSeparators(let line):
            return "choose takes one '|' between the list and the action; quote any other,"
                + " in '\(line)'"
        }
    }
}
