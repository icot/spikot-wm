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

    /// Actions by the name written on the command line, with Rectangle's own spelling accepted
    /// alongside the hyphenated one so a binding can be copied from its settings.
    static let byName: [String: PlacementAction] = [
        "left-half": .leftHalf, "lefthalf": .leftHalf,
        "right-half": .rightHalf, "righthalf": .rightHalf,
        "top-half": .topHalf, "tophalf": .topHalf,
        "bottom-half": .bottomHalf, "bottomhalf": .bottomHalf,
        "maximize": .maximize, "max": .maximize,
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
        ["<stack index>"] + ["left-half", "right-half", "top-half", "bottom-half", "maximize"]
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
        }
    }

    /// Whether a repeated press cycles the size, as Rectangle's default does.
    ///
    /// `maximize` does not: there is nothing between maximized and maximized.
    var cycles: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return true
        case .stack, .maximize: return false
        }
    }

    /// Which edges of the result touch another window rather than the screen edge.
    ///
    /// Rectangle's table, `WindowAction.gapSharedEdge` (`Rectangle/WindowAction.swift:808`).
    var gapSharedEdges: Gap.Edge {
        switch self {
        case .leftHalf: return .right
        case .rightHalf: return .left
        case .topHalf: return .bottom
        case .bottomHalf: return .top
        case .maximize, .stack: return .none
        }
    }
}

/// The geometry of each placement action, in AppKit's bottom-left coordinates.
///
/// Ported from `Rectangle/WindowCalculation/`, in the shape the default configuration takes:
/// `LeftRightHalfCalculation`, `TopHalfCalculation`, `BottomHalfCalculation` and
/// `MaximizeCalculation`, each of which reduces to `HalfSplitFrameCalculation` plus
/// `GapCalculation.applyGaps`.
///
/// What is deliberately **not** ported: `halvesPreserveOtherAxisSize`, `acrossMonitor` and
/// `acrossAndResize` subsequent-execution modes, corner actions, prominence, and the
/// `ActiveSideSplitRatios` that remember a dragged divider. None is enabled in the captured
/// `com.knollsoft.Hookshot` defaults, so porting them would be writing code against no
/// observable behaviour.
public enum Placement {

    /// Sizes a repeated press cycles through, in Rectangle's order.
    ///
    /// Its default set is `[oneHalf, twoThirds, oneThird]` and `CycleSize.sortedSizes` orders it
    /// as the first size, then the larger ones, then the smaller: a half, two thirds, a third.
    /// `subsequentExecutionMode` is unset in the captured defaults, which
    /// `SubsequentExecutionMode(rawValue: 0)` reads as `.resize`, so this cycling is what a
    /// repeated `cmd-shift-1` does today.
    public static let cycleFractions: [CGFloat] = [1.0 / 2.0, 2.0 / 3.0, 1.0 / 3.0]

    /// Rectangle rounds a computed dimension down, with a hair of tolerance so a value that is
    /// a floating-point whisker under an integer does not lose a whole pixel.
    /// `HalfSplitFrameCalculation.floorDimension`, tolerance 0.0001.
    static func floorDimension(_ value: CGFloat) -> CGFloat {
        (value + 0.0001).rounded(.down)
    }

    /// The rect an action puts a window in, gaps included.
    ///
    /// `repeats` is how many times this same action has already been applied to this window in a
    /// row: 0 for a fresh press, which takes the first fraction. Cycling therefore needs someone
    /// to remember the last action, which is the agent; a one-shot CLI run always passes 0 and
    /// so always produces the first rect.
    public static func rect(
        for action: PlacementAction, in visibleFrame: CGRect, gap: Int, repeats: Int = 0
    ) -> CGRect {
        let fraction = action.cycles ? cycleFractions[repeats % cycleFractions.count] : 1
        var raw = visibleFrame

        switch action {
        case .maximize, .stack:
            break
        case .leftHalf, .rightHalf:
            raw.size.width = floorDimension(visibleFrame.width * fraction)
            if action == .rightHalf { raw.origin.x = visibleFrame.maxX - raw.width }
        case .topHalf, .bottomHalf:
            raw.size.height = floorDimension(visibleFrame.height * fraction)
            // Bottom-left origin: the top half is the one whose origin is pushed up.
            if action == .topHalf { raw.origin.y = visibleFrame.maxY - raw.height }
        }

        return Gap.apply(to: raw, size: gap, sharedEdges: action.gapSharedEdges)
    }
}

/// What was last done to a window, so a repeated press can cycle.
///
/// Rectangle's `lastAction`, reduced to what the cycling needs: which action, and how many times
/// in a row. Lives in the agent because a one-shot CLI process has nowhere to keep it.
public struct LastAction: Equatable, Sendable {
    public let action: String
    public let count: Int

    public init(action: String, count: Int) {
        self.action = action
        self.count = count
    }

    /// The count to record after applying `action` again, given what came before.
    public static func advancing(_ previous: LastAction?, with action: PlacementAction) -> LastAction {
        guard let previous, previous.action == action.name else {
            return LastAction(action: action.name, count: 1)
        }
        return LastAction(action: action.name, count: previous.count + 1)
    }

    /// How many repeats to pass to `Placement.rect` for the press being handled now.
    public static func repeats(_ previous: LastAction?, for action: PlacementAction) -> Int {
        guard let previous, previous.action == action.name else { return 0 }
        return previous.count
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
        }
    }

    /// The `Response.Failure.code` this error travels as.
    public var ipcCode: String {
        switch self {
        case .unknownAction, .negativeStack: return "usage"
        case .noPlacement: return "stackOutOfRange"
        case .noDisplays: return "failure"
        case .elementNotFound: return "unknownWindow"
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
        _ action: PlacementAction, windowNumber: Int, repeats: Int = 0
    ) throws -> PlacementResult {
        guard let window = visibleWindows.first(where: { $0.kCGWindowNumber == windowNumber })
        else {
            throw StackError.unknownWindow(windowNumber)
        }
        return try place(action, window: window, repeats: repeats)
    }

    /// Places the frontmost application's first window, the way `spikot-placer` chose one.
    ///
    /// Kept for the no-argument case, and reported as a guess: `focus` has the same limitation
    /// and it is what `currentStack()` documents.
    @discardableResult
    public func placeFrontmost(
        _ action: PlacementAction, repeats: Int = 0
    ) throws -> PlacementResult {
        try place(action, windowNumber: try frontmostWindowNumber(), repeats: repeats)
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
        _ action: PlacementAction, window: Window, repeats: Int = 0
    ) throws -> PlacementResult {
        let displays = displaySource.displays()
        guard !displays.isEmpty else { throw PlacementError.noDisplays }

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

        try write(rect, to: window)
        if case .stack(let index) = action { assign(window, toStack: index) }

        return PlacementResult(
            windowNumber: window.kCGWindowNumber, owner: window.kCGWindowOwnerName,
            action: action.name, rect: rect, display: display)
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
