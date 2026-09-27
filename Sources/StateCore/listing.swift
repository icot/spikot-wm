import CoreGraphics
import Foundation

/// Output shapes for `spikot-wm list`.
public enum ListFormat: String, CaseIterable, Sendable {
    /// The original layout: window number, owner name, owner pid, padded and joined with
    /// "\t| ". Still the default because ~/.local/bin/mylauncher parses it, taking field 3.
    /// Do not change it; spikot-win-9ic.3 switches the default once that script is gone.
    case legacy
    /// Tab-separated, one header line, with the title and stack index the legacy format
    /// has no room for.
    case tsv
    /// The same fields as an array of objects.
    case json
}

// Human-readable output, moved out of state.swift to keep that file under the line
// limit and to keep presentation separate from the state machine.
extension State {

    public func listWindows() -> String {
        var buf: [String] = []
        for window in self.visibleWindows where !isIgnored(window) {
            let info: [String] = [
                String(window.kCGWindowNumber).padding(
                    toLength: 10, withPad: " ", startingAt: 0),
                window.kCGWindowOwnerName.padding(toLength: 32, withPad: " ", startingAt: 0),
                String(window.kCGWindowOwnerPID).padding(
                    toLength: 10, withPad: " ", startingAt: 0),
            ]

            buf.append(info.joined(separator: "\t| "))
        }
        return buf.joined(separator: "\n")
    }

    public func sprintfStacks() -> String {
        var buf: [String] = []
        for stack in self.stacks {
            buf.append((stack.map { $0.kCGWindowOwnerName }).joined(separator: ", "))
        }
        return buf.joined(separator: "|")
    }

    /// The per-stack report, exactly as `printfStacks()` writes it.
    ///
    /// Extracted so the agent can put the same bytes in a response without a second
    /// implementation that could drift from the printed one.
    public func stacksReport() -> String {
        var lines: [String] = []
        for (index, stack) in self.stacks.enumerated() {
            lines.append("Stack [\(index)]")
            let names = stack.filter { !isIgnored($0) }.map { $0.kCGWindowOwnerName }
            lines.append(names.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    public func printfStacks() {
        print(stacksReport())
    }

    func sprintfSet(inSet: Set<WindowMeta>) -> String {
        var buf: [String] = []
        for item in inSet {
            buf.append(item.kCGWindowOwnerName)
        }
        return buf.joined(separator: ", ")
    }

    /// Renders the visible windows.
    ///
    /// `tsv` and `json` include the title, which costs one Accessibility round-trip per
    /// window; `legacy` does not and stays as cheap as it was.
    public func listWindows(format: ListFormat) throws -> String {
        switch format {
        case .legacy:
            return listWindows()
        case .tsv:
            let header = ["windowId", "pid", "app", "stack", "title"].joined(separator: "\t")
            let rows = managedWindows().map { window in
                [
                    String(window.kCGWindowNumber),
                    String(window.kCGWindowOwnerPID),
                    window.kCGWindowOwnerName,
                    stackIndex(of: window).map(String.init) ?? "-",
                    title(for: window) ?? "",
                ].joined(separator: "\t")
            }
            return ([header] + rows).joined(separator: "\n")
        case .json:
            let entries = managedWindows().map { window in
                ListedWindow(
                    windowId: window.kCGWindowNumber,
                    pid: window.kCGWindowOwnerPID,
                    app: window.kCGWindowOwnerName,
                    stack: stackIndex(of: window),
                    title: title(for: window),
                    bounds: .init(window.kCGWindowBounds))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(bytes: try encoder.encode(entries), encoding: .utf8) ?? "[]"
        }
    }

    /// Visible windows minus the ignored applications.
    func managedWindows() -> [Window] {
        visibleWindows.filter { !isIgnored($0) }
    }
}

/// One row of `list --format json`.
///
/// A separate type from `Window` on purpose: this is an output contract that should not
/// shift when the CGWindowList fields spikot-wm happens to collect change.
public struct ListedWindow: Codable, Equatable {
    public struct Bounds: Codable, Equatable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        init(_ bounds: WindowBounds) {
            self.x = bounds.coordX
            self.y = bounds.coordY
            self.width = bounds.width
            self.height = bounds.height
        }
    }

    public var windowId: Int
    public var pid: Int32
    public var app: String
    public var stack: Int?
    public var title: String?
    public var bounds: Bounds
}
