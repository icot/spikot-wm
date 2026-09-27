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

    /// Parses a command-line argument.
    ///
    /// A bare number is a stack index, so `place 1` means what `spikot-placer 1` meant.
    public static func parse(_ raw: String) throws -> PlacementAction {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let index = Int(trimmed) {
            guard index >= 0 else { throw PlacementError.negativeStack(index) }
            return .stack(index)
        }
        throw PlacementError.unknownAction(trimmed, known: PlacementAction.names)
    }

    /// Every accepted spelling, for help text and error messages.
    public static var names: [String] { ["<stack index>"] }

    /// Canonical name, for logs and for the per-window action history.
    public var name: String {
        switch self {
        case .stack(let index): return "stack \(index)"
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
    public func place(_ action: PlacementAction, windowNumber: Int) throws -> PlacementResult {
        guard let window = visibleWindows.first(where: { $0.kCGWindowNumber == windowNumber })
        else {
            throw StackError.unknownWindow(windowNumber)
        }
        return try place(action, window: window)
    }

    /// Places the frontmost application's first window, the way `spikot-placer` chose one.
    ///
    /// Kept for the no-argument case, and reported as a guess: `focus` has the same limitation
    /// and it is what `currentStack()` documents.
    @discardableResult
    public func placeFrontmost(_ action: PlacementAction) throws -> PlacementResult {
        guard let pid = focusSource.frontmostPID else { throw StackError.noCurrentStack }
        guard let window = visibleWindows.first(where: { $0.kCGWindowOwnerPID == pid }) else {
            throw StackError.unknownProcess(pid)
        }
        return try place(action, window: window)
    }

    @discardableResult
    func place(_ action: PlacementAction, window: Window) throws -> PlacementResult {
        let displays = displaySource.displays()
        guard !displays.isEmpty else { throw PlacementError.noDisplays }

        let target: StackPlacement
        switch action {
        case .stack(let index):
            // Guarded, unlike `spikot-placer`, whose argument list allowed 3 and 4 while
            // `stacks[targetStack]` was unchecked, so `spikot-placer 4` on a two-stack layout
            // trapped.
            guard let placement = stackLayout().first(where: { $0.stack == index }) else {
                throw PlacementError.noPlacement(stack: index, stacks: activeMode.count)
            }
            target = placement
        }

        try write(target.axFrame, to: window)
        if case .stack(let index) = action { assign(window, toStack: index) }

        return PlacementResult(
            windowNumber: window.kCGWindowNumber, owner: window.kCGWindowOwnerName,
            action: action.name, rect: target.axFrame, display: target.display)
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
