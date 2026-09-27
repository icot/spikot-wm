import Cocoa
import Foundation

/// What `spikot-wm place` can do to a window.
///
/// Grows one case per shipped action rather than listing the whole roadmap, so the enum never
/// claims something the code cannot do.
public enum PlacementAction: Equatable, Sendable {
    /// Move to a columnar stack, which is `spikot-placer`'s only trick and the one action that
    /// belongs to spikot-wm's own model rather than to Rectangle's.
    case stack(Int)
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds
    case nextDisplay
    case previousDisplay
    case restore

    /// Actions by the name written on the command line, with Rectangle's own spelling accepted
    /// alongside the hyphenated one so a binding can be copied from its settings.
    static let byName: [String: PlacementAction] = [
        "left-half": .leftHalf, "lefthalf": .leftHalf,
        "right-half": .rightHalf, "righthalf": .rightHalf,
        "top-half": .topHalf, "tophalf": .topHalf,
        "bottom-half": .bottomHalf, "bottomhalf": .bottomHalf,
        "maximize": .maximize, "max": .maximize,
        "first-third": .firstThird, "firstthird": .firstThird, "left-third": .firstThird,
        "center-third": .centerThird, "centerthird": .centerThird,
        "last-third": .lastThird, "lastthird": .lastThird, "right-third": .lastThird,
        "first-two-thirds": .firstTwoThirds, "firsttwothirds": .firstTwoThirds,
        "last-two-thirds": .lastTwoThirds, "lasttwothirds": .lastTwoThirds,
        "next-display": .nextDisplay, "nextdisplay": .nextDisplay,
        "previous-display": .previousDisplay, "previousdisplay": .previousDisplay,
        "prev-display": .previousDisplay,
        "restore": .restore,
    ]

    /// Parses a command-line argument.
    ///
    /// A bare number is a stack index, so `place 1` means what `spikot-placer 1` meant.
    public static func parse(_ raw: String) throws -> PlacementAction {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let index = Int(trimmed) {
            guard index >= 0 else { throw PlacementError.negativeStack(index) }
            return .stack(index)
        }
        if let action = byName[trimmed.lowercased()] { return action }
        throw PlacementError.unknownAction(trimmed, known: PlacementAction.names)
    }

    /// Every accepted spelling, for help text and error messages.
    public static var names: [String] {
        ["<stack index>"]
            + [
                "left-half", "right-half", "top-half", "bottom-half", "maximize",
                "first-third", "center-third", "last-third",
                "first-two-thirds", "last-two-thirds",
                "next-display", "previous-display", "restore",
            ]
    }

    /// Canonical name, for logs and for the per-window action history.
    public var name: String {
        switch self {
        case .stack(let index): return "stack \(index)"
        case .leftHalf: return "left-half"
        case .rightHalf: return "right-half"
        case .topHalf: return "top-half"
        case .bottomHalf: return "bottom-half"
        case .maximize: return "maximize"
        case .firstThird: return "first-third"
        case .centerThird: return "center-third"
        case .lastThird: return "last-third"
        case .firstTwoThirds: return "first-two-thirds"
        case .lastTwoThirds: return "last-two-thirds"
        case .nextDisplay: return "next-display"
        case .previousDisplay: return "previous-display"
        case .restore: return "restore"
        }
    }

    /// Whether a repeated press cycles the size, as Rectangle's default does.
    ///
    /// `maximize` does not: there is nothing between maximized and maximized.
    var cycles: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return true
        // The thirds do not cycle. Rectangle instead walks first -> center -> last on a
        // repeat, through its subAction bookkeeping; see the note in Placement.
        case .stack, .maximize, .firstThird, .centerThird, .lastThird,
            .firstTwoThirds, .lastTwoThirds, .nextDisplay, .previousDisplay, .restore:
            return false
        }
    }

    /// Whether this action should record where the window was, for `restore` to come back to.
    ///
    /// False for `restore` itself, which would otherwise record the frame it is about to leave and
    /// so make every restore a no-op after the first. Rectangle carries the same flag as
    /// `updateRestoreRect`.
    var updatesRestorePoint: Bool { self != .restore }

    /// Which edges of the result touch another window rather than the screen edge.
    ///
    /// Rectangle's table, `WindowAction.gapSharedEdge` (`Rectangle/WindowAction.swift:808`).
    func gapSharedEdges(landscape: Bool) -> Gap.Edge {
        switch self {
        case .leftHalf: return .right
        case .rightHalf: return .left
        case .topHalf: return .bottom
        case .bottomHalf: return .top
        case .maximize, .stack, .nextDisplay, .previousDisplay, .restore: return .none
        // The thirds share whichever edges face their neighbours, which depends on the axis
        // they were split along: Rectangle's subAction table, WindowAction.swift:1043.
        case .firstThird, .firstTwoThirds: return landscape ? .right : .bottom
        case .lastThird, .lastTwoThirds: return landscape ? .left : .top
        case .centerThird: return landscape ? [.left, .right] : [.top, .bottom]
        }
    }
}

/// Why a placement could not be carried out.
public enum PlacementError: Error, CustomStringConvertible, Equatable {
    case unknownAction(String, known: [String])
    case negativeStack(Int)
    case noPlacement(stack: Int, stacks: Int)
    case noDisplays
    case elementNotFound(Int)
    case writeRefused(Int)
    case singleDisplay
    case nothingToRestore(Int)

    public var description: String {
        switch self {
        case .unknownAction(let raw, let known):
            return "unrecognised placement '\(raw)'; expected " + known.joined(separator: ", ")
        case .negativeStack(let index):
            return "stack \(index) is not a stack index"
        case .noPlacement(let stack, let stacks):
            return "stack \(stack) does not exist; the current layout has \(stacks)"
        case .noDisplays:
            return "no displays are attached, so there is nowhere to place a window"
        case .elementNotFound(let number):
            return "window \(number) has no Accessibility element, so it cannot be moved"
        case .writeRefused(let number):
            return "window \(number) refused the new position or size"
        case .singleDisplay:
            return "there is only one display, so there is no next or previous one"
        case .nothingToRestore(let number):
            return "nothing recorded for window \(number): it has not been placed since the"
                + " agent started, and without the agent there is nowhere to record it"
        }
    }

    /// The `Response.Failure.code` this error travels as.
    public var ipcCode: String {
        switch self {
        case .unknownAction, .negativeStack: return "usage"
        case .noPlacement: return "stackOutOfRange"
        case .noDisplays, .singleDisplay: return "failure"
        case .elementNotFound: return "unknownWindow"
        case .nothingToRestore: return "notFound"
        case .writeRefused: return "failure"
        }
    }
}

/// The outcome of a placement, so a caller can report what happened without re-deriving it.
public struct PlacementResult: Equatable, Sendable {
    public let windowNumber: Int
    public let owner: String
    public let action: String
    /// Where the window was asked to go, in the Accessibility API's coordinates.
    public let rect: CGRect
    /// Which display it landed on, as an index into the display list.
    public let display: Int

    public init(windowNumber: Int, owner: String, action: String, rect: CGRect, display: Int) {
        self.windowNumber = windowNumber
        self.owner = owner
        self.action = action
        self.rect = rect
        self.display = display
    }

    /// One line, which is what the CLI prints.
    public var summary: String {
        "\(owner) \(windowNumber) -> \(action) on display \(display):"
            + " \(Int(rect.width))x\(Int(rect.height))@(\(Int(rect.minX)),\(Int(rect.minY)))"
    }
}

extension State {

    /// Carries out a placement on one window.
    ///
    /// The window is named rather than assumed. `spikot-placer` took the frontmost
    /// *application* and then the first `CGWindow` with that pid, so with two Firefox windows it
    /// moved whichever the window server listed first, which is not necessarily the one in
    /// front. `modifyWindow` could always place any on-screen window; nothing exposed it.
    @discardableResult
    public func place(
        _ action: PlacementAction, windowNumber: Int, history: WindowHistory? = nil
    ) throws -> PlacementResult {
        guard let window = visibleWindows.first(where: { $0.kCGWindowNumber == windowNumber })
        else {
            throw StackError.unknownWindow(windowNumber)
        }
        return try place(action, window: window, history: history)
    }

    /// Places the frontmost application's first window, the way `spikot-placer` chose one.
    ///
    /// Kept for the no-argument case, and reported as a guess: `focus` has the same limitation
    /// and it is what `currentStack()` documents.
    @discardableResult
    public func placeFrontmost(
        _ action: PlacementAction, history: WindowHistory? = nil
    ) throws -> PlacementResult {
        try place(action, windowNumber: try frontmostWindowNumber(), history: history)
    }

    /// The window `place` and `spikot-placer` act on when none is named.
    ///
    /// The frontmost application's first on-screen window, which is a guess when it has several:
    /// `CGWindowList` order is not focus order. Exposed so a caller that needs the window number
    /// before placing — the agent, to look up what it last did to that window — does not have to
    /// repeat the guess differently.
    public func frontmostWindowNumber() throws -> Int {
        guard let pid = focusSource.frontmostPID else { throw StackError.noCurrentStack }
        guard let window = visibleWindows.first(where: { $0.kCGWindowOwnerPID == pid }) else {
            throw StackError.unknownProcess(pid)
        }
        return window.kCGWindowNumber
    }

    @discardableResult
    func place(
        _ action: PlacementAction, window: Window, history: WindowHistory? = nil
    ) throws -> PlacementResult {
        let displays = displaySource.displays()
        guard !displays.isEmpty else { throw PlacementError.noDisplays }

        // Recorded before anything moves, and only when there is nothing recorded yet or the user
        // has moved the window since. Without a history - a CLI run with no agent - there is
        // nothing to restore to, which `restore` reports rather than guessing.
        if action.updatesRestorePoint {
            history?.noteFrameBeforePlacing(
                window.kCGWindowBounds.rect, window: window.kCGWindowNumber)
        }
        let repeats = history?.repeats(of: action, window: window.kCGWindowNumber) ?? 0

        let (rect, display) = try target(
            for: action, window: window, displays: displays, repeats: repeats, history: history)

        try write(rect, to: window)
        if case .stack(let index) = action { assign(window, toStack: index) }
        history?.note(action, window: window.kCGWindowNumber, resulting: rect)

        return PlacementResult(
            windowNumber: window.kCGWindowNumber, owner: window.kCGWindowOwnerName,
            action: action.name, rect: rect, display: display)
    }

    /// Where an action wants the window, in the Accessibility API's coordinates, and on which
    /// display. Split out from `place` so the arithmetic is separate from the writing.
    private func target(
        for action: PlacementAction, window: Window, displays: [DisplayInfo], repeats: Int,
        history: WindowHistory?
    ) throws -> (rect: CGRect, display: Int) {
        let rect: CGRect
        let display: Int
        switch action {
        case .stack(let index):
            // Guarded, unlike `spikot-placer`, whose argument list allowed 3 and 4 while
            // `stacks[targetStack]` was unchecked, so `spikot-placer 4` on a two-stack layout
            // trapped.
            guard let placement = stackLayout().first(where: { $0.stack == index }) else {
                throw PlacementError.noPlacement(stack: index, stacks: activeMode.count)
            }
            rect = placement.axFrame
            display = placement.display
        case .restore:
            guard let previous = history?.restoreRect(window: window.kCGWindowNumber) else {
                throw PlacementError.nothingToRestore(window.kCGWindowNumber)
            }
            rect = previous
            display = Geometry.display(containingWindow: previous, in: displays)

        case .nextDisplay, .previousDisplay:
            let axis = Geometry.flipAxis(displays)
            let current = Geometry.display(
                containingWindow: window.kCGWindowBounds.rect, in: displays)
            guard let target = Geometry.adjacentDisplay(
                to: current, in: displays, forward: action == .nextDisplay)
            else {
                throw PlacementError.singleDisplay
            }
            display = target
            let inAppKitSpace = Geometry.flipped(window.kCGWindowBounds.rect, axis: axis)
            let transferred = DisplayTransfer.transferredRect(
                window: inAppKitSpace,
                source: displays[current].visibleFrame,
                destination: displays[target].visibleFrame,
                tolerance: DisplayTransfer.edgeTolerance(gap: config.gap))
            // Against all four edges means the window was maximized, so it is maximized on the
            // destination rather than stretched by the transfer. Rectangle does the same.
            let moved =
                transferred.sharedEdges == .all
                ? Placement.rect(
                    for: .maximize, in: displays[target].visibleFrame, gap: config.gap)
                : transferred.rect
            rect = Geometry.flipped(moved, axis: axis)

        default:
            // The action applies to the display the window is on, which is Rectangle's rule
            // too: everything is relative to the current screen, not the main one.
            display = Geometry.display(
                containingWindow: window.kCGWindowBounds.rect, in: displays)
            let computed = Placement.rect(
                for: action, in: displays[display].visibleFrame, gap: config.gap,
                repeats: repeats)
            rect = Geometry.flipped(computed, axis: Geometry.flipAxis(displays))
        }
        return (rect, display)
    }

    /// Writes a frame through the Accessibility API.
    func write(_ rect: CGRect, to window: Window) throws {
        guard
            let found = WindowIdentity.element(
                forWindowID: CGWindowID(window.kCGWindowNumber),
                pid: window.kCGWindowOwnerPID,
                bounds: window.kCGWindowBounds.rect)
        else {
            throw PlacementError.elementNotFound(window.kCGWindowNumber)
        }
        guard WindowIdentity.setFrame(rect, on: found.element) else {
            throw PlacementError.writeRefused(window.kCGWindowNumber)
        }
    }

    /// Moves a window's stack membership, and persists it.
    ///
    /// Without this the window would snap back to the stack its coordinates imply on the next
    /// run, since stack membership is derived from position and then merged with the cache.
    func assign(_ window: Window, toStack index: Int) {
        for stack in stacks.indices {
            stacks[stack].removeAll { $0.kCGWindowNumber == window.kCGWindowNumber }
        }
        guard stacks.indices.contains(index) else {
            logger.error("Stack \(index) is outside the \(self.stacks.count) computed stacks")
            return
        }
        stacks[index].insert(window, at: 0)
        flushCurrentState()
    }
}
