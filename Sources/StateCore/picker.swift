import Foundation

/// The picker's list, filter and selection, with no AppKit in it.
///
/// Here rather than in the agent for the same reason hotkey parsing is: the agent has no test
/// target, and this is the part with behaviour worth pinning down. What is left in
/// `Sources/Agent/Picker.swift` is the panel and the key codes.
public struct PickerModel: Equatable, Sendable {
    /// One choice: a window number and the line shown for it.
    public struct Row: Equatable, Sendable {
        public let window: Int
        public let label: String

        public init(window: Int, label: String) {
            self.window = window
            self.label = label
        }
    }

    public let rows: [Row]
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
