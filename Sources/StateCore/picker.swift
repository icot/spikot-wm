// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The picker's list, filter and selection, with no AppKit in it.
///
/// Here rather than in the agent for the same reason hotkey parsing is: the agent has no test
/// target, and this is the part with behaviour worth pinning down. What is left in
/// `Sources/Agent/Picker.swift` is the panel and the key codes.
public struct PickerModel: Equatable, Sendable {
    /// One choice: what picking it means to the caller, and the line shown for it.
    public struct Row: Equatable, Sendable {
        /// A window number for `pick` and `launch`, an index into the list for `choose`.
        public let id: Int
        public let label: String

        public init(id: Int, label: String) {
            self.id = id
            self.label = label
        }
    }

    public private(set) var rows: [Row]
    public private(set) var filter = ""
    /// Index into `matches`, not into `rows`.
    public private(set) var selection = 0

    public init(rows: [Row]) {
        self.rows = rows
    }

    /// Rows matching the filter, in the order they were given.
    ///
    /// Case-insensitive substring over the whole line, so either the application name or the window
    /// title narrows the list.
    public var matches: [Row] {
        guard !filter.isEmpty else { return rows }
        let wanted = filter.lowercased()
        return rows.filter { $0.label.lowercased().contains(wanted) }
    }

    /// The highlighted row, or nil when the filter matches nothing.
    public var selected: Row? {
        let matches = self.matches
        guard matches.indices.contains(selection) else { return nil }
        return matches[selection]
    }

    /// Replaces the list and keeps what has been typed, for a list that arrives after the panel
    /// is already up — `choose` shows the panel on the keypress and fills it when its command
    /// finishes, and anything typed in between still applies.
    public mutating func replaceRows(_ rows: [Row]) {
        self.rows = rows
        clampSelection()
    }

    /// Appends to the filter, keeping the selection inside the new list.
    public mutating func type(_ text: String) {
        filter.append(contentsOf: text)
        clampSelection()
    }

    /// Removes the last character of the filter.
    public mutating func backspace() {
        guard !filter.isEmpty else { return }
        filter.removeLast()
        clampSelection()
    }

    /// Moves the highlight, wrapping at both ends so Up from the first row reaches the last.
    public mutating func move(by offset: Int) {
        let count = matches.count
        guard count > 0 else { return }
        selection = (selection + offset % count + count) % count
    }

    /// The row a number key picks, or nil when there is no such row. 1 is the first.
    public func row(forNumberKey number: Int) -> Row? {
        let matches = self.matches
        let index = number - 1
        guard matches.indices.contains(index) else { return nil }
        return matches[index]
    }

    private mutating func clampSelection() {
        selection = min(selection, max(0, matches.count - 1))
    }
}
