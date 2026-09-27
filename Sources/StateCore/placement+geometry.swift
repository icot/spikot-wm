import CoreGraphics
import Foundation

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

        let landscape = visibleFrame.width > visibleFrame.height

        switch action {
        // A display move is not a rect on one screen, so it is not computed here: State.place
        // resolves it through DisplayTransfer, which needs both screens and the window.
        // Neither a display move nor a restore is a rect on one screen: State.place resolves
        // them, through DisplayTransfer and through the recorded frame respectively.
        case .maximize, .stack, .nextDisplay, .previousDisplay, .restore:
            break
        case .leftHalf, .rightHalf:
            raw.size.width = floorDimension(visibleFrame.width * fraction)
            if action == .rightHalf { raw.origin.x = visibleFrame.maxX - raw.width }
        case .topHalf, .bottomHalf:
            raw.size.height = floorDimension(visibleFrame.height * fraction)
            // Bottom-left origin: the top half is the one whose origin is pushed up.
            if action == .topHalf { raw.origin.y = visibleFrame.maxY - raw.height }
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            raw = thirdRect(action, in: visibleFrame, landscape: landscape)
        }

        return Gap.apply(
            to: raw, size: gap, sharedEdges: action.gapSharedEdges(landscape: landscape))
    }

    /// The thirds and two-thirds, split along the display's long axis.
    ///
    /// Orientation-aware as Rectangle's are (`OrientationAware`, `landscapeRect` against
    /// `portraitRect`): on a portrait display the "first third" is the top one. No portrait
    /// display has ever been attached to this machine, so that half is ported from the source and
    /// unobserved.
    ///
    /// Note `centerThird`'s asymmetry, which is Rectangle's and is kept for parity: the origin is
    /// floored while the size is the exact third (`CenterThirdCalculation.swift:14-17`). On a
    /// 3440-wide display that puts the centre third at x = 1146 with width 1146.67, so the three
    /// thirds do not tile to the pixel — the last third starts at 2293 while the centre ends at
    /// 2292.67. A third of a pixel, and matching Rectangle matters more than closing it.
    static func thirdRect(
        _ action: PlacementAction, in visibleFrame: CGRect, landscape: Bool
    ) -> CGRect {
        var rect = visibleFrame
        let fraction: CGFloat = (action == .firstTwoThirds || action == .lastTwoThirds)
            ? 2.0 / 3.0 : 1.0 / 3.0

        if landscape {
            switch action {
            case .centerThird:
                rect.origin.x = visibleFrame.minX + (visibleFrame.width / 3).rounded(.down)
                rect.size.width = visibleFrame.width / 3
            case .lastThird, .lastTwoThirds:
                rect.size.width = (visibleFrame.width * fraction).rounded(.down)
                rect.origin.x = visibleFrame.maxX - rect.width
            default:
                rect.size.width = (visibleFrame.width * fraction).rounded(.down)
            }
        } else {
            switch action {
            case .centerThird:
                rect.origin.y = visibleFrame.minY + (visibleFrame.height / 3).rounded(.down)
                rect.size.height = visibleFrame.height / 3
            case .lastThird, .lastTwoThirds:
                // "Last" is the bottom in a portrait split, so it keeps the frame's origin.
                rect.size.height = (visibleFrame.height * fraction).rounded(.down)
            default:
                // "First" is the top, so its origin moves up.
                rect.size.height = (visibleFrame.height * fraction).rounded(.down)
                rect.origin.y = visibleFrame.maxY - rect.height
            }
        }
        return rect
    }
}

/// What was last done to a window, so a repeated press can cycle.
///
/// Rectangle's `lastAction`, reduced to what the cycling needs: which action, and how many times
/// in a row. Lives in the agent because a one-shot CLI process has nowhere to keep it.
public struct LastAction: Equatable, Sendable {
    public let action: String
    public let count: Int
    /// The frame the action produced, in the Accessibility API's coordinates.
    ///
    /// Kept so a later placement can tell "the window is where we left it" from "the user has
    /// moved it since", which is what decides whether the restore point is refreshed.
    public let rect: CGRect

    public init(action: String, count: Int, rect: CGRect = .null) {
        self.action = action
        self.count = count
        self.rect = rect
    }

    /// The count to record after applying `action` again, given what came before.
    public static func advancing(
        _ previous: LastAction?, with action: PlacementAction, rect: CGRect = .null
    ) -> LastAction {
        guard let previous, previous.action == action.name else {
            return LastAction(action: action.name, count: 1, rect: rect)
        }
        return LastAction(action: action.name, count: previous.count + 1, rect: rect)
    }

    /// How many repeats to pass to `Placement.rect` for the press being handled now.
    public static func repeats(_ previous: LastAction?, for action: PlacementAction) -> Int {
        guard let previous, previous.action == action.name else { return 0 }
        return previous.count
    }
}

/// Moving a window to another display, ported from `Rectangle/WindowCalculation/DisplayTransfer`.
///
/// Rectangle v2.0 does not remap proportionally, which is what the plan assumed. It works each
/// axis separately and follows the screen edges the window was against: against both, the window
/// spans that axis on the destination, so a maximized window stays maximized; against one, it
/// keeps its size and stays against that edge, so a window in a corner arrives in the same
/// corner; against neither, it keeps its size and its centre keeps the same relative position.
/// The distance from an edge carries over, so a window snapped with gaps arrives with the same
/// gaps — which is why no gap is applied on top.
public enum DisplayTransfer {

    /// One axis: where the thing starts and how long it is.
    typealias Span = (origin: CGFloat, length: CGFloat)

    /// Which of an axis's two screen edges the window was against.
    enum Contact {
        case neither, start, end, both

        var isOneEdge: Bool { self == .start || self == .end }
    }

    /// How far from a screen edge a window edge can be and still count as against it.
    ///
    /// Rectangle's `4 + gapSize`: windows are rarely at the exact point — the Accessibility API
    /// rounds and applications round to their own grid — and with gaps nothing is ever flush.
    public static func edgeTolerance(gap: Int) -> CGFloat { 4 + CGFloat(gap) }

    /// Where a window lands on another display, and which destination edges it ends up against.
    ///
    /// All rects in AppKit's bottom-left space, the same as `Placement.rect`.
    public static func transferredRect(
        window: CGRect, source: CGRect, destination: CGRect, tolerance: CGFloat
    ) -> (rect: CGRect, sharedEdges: Gap.Edge) {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0
        else {
            return (window, .none)
        }

        var horizontal = transfer(
            window: (window.minX, window.width), source: (source.minX, source.width),
            destination: (destination.minX, destination.width), tolerance: tolerance)
        var vertical = transfer(
            window: (window.minY, window.height), source: (source.minY, source.height),
            destination: (destination.minY, destination.height), tolerance: tolerance)

        if changesOrientation(from: source, to: destination) {
            // Against three edges — spanning one axis, against one edge of the other — would
            // stretch a left half into a sliver down a portrait display. Centre the spanning axis
            // instead, which assumes nothing about how the displays are arranged.
            if horizontal.contact == .both, vertical.contact.isOneEdge {
                horizontal.span = centred(
                    length: window.width, on: horizontal.span,
                    destination: (destination.minX, destination.width))
            } else if vertical.contact == .both, horizontal.contact.isOneEdge {
                vertical.span = centred(
                    length: window.height, on: vertical.span,
                    destination: (destination.minY, destination.height))
            }
        }

        let rect = CGRect(
            x: horizontal.span.origin, y: vertical.span.origin,
            width: horizontal.span.length, height: vertical.span.length)
        return (rect, edges(horizontal: horizontal.contact, vertical: vertical.contact))
    }

    /// Landscape to portrait or back. A square display is neither, so it never counts.
    static func changesOrientation(from source: CGRect, to destination: CGRect) -> Bool {
        (source.width > source.height && destination.height > destination.width)
            || (source.height > source.width && destination.width > destination.height)
    }

    /// Keeps the length and centres it, rather than following both edges.
    static func centred(length: CGFloat, on spanned: Span, destination: Span) -> Span {
        guard length < spanned.length else { return spanned }
        return (destination.origin + (destination.length - length) / 2, length)
    }

    static func transfer(
        window: Span, source: Span, destination: Span, tolerance: CGFloat
    ) -> (span: Span, contact: Contact) {
        // A window hanging off the screen has a negative inset, which counts as against that
        // edge: bringing it back into view is the only sensible thing to do with it.
        let startInset = window.origin - source.origin
        let endInset = (source.origin + source.length) - (window.origin + window.length)
        let againstStart = startInset <= tolerance
        let againstEnd = endInset <= tolerance

        if againstStart, againstEnd {
            let start = clamp(startInset, 0, destination.length / 2)
            let end = clamp(endInset, 0, destination.length / 2)
            return ((destination.origin + start, destination.length - start - end), .both)
        }

        let length = min(window.length, destination.length)
        let slack = destination.length - length

        if againstStart {
            return ((destination.origin + clamp(startInset, 0, slack), length), .start)
        }
        if againstEnd {
            return (
                (destination.origin + destination.length - length - clamp(endInset, 0, slack),
                 length), .end)
        }

        let centreFraction = (window.origin + window.length / 2 - source.origin) / source.length
        let origin = destination.origin + centreFraction * destination.length - length / 2
        return ((clamp(origin, destination.origin, destination.origin + slack), length), .neither)
    }

    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    /// The contacts as edges, so `.all` can be recognised: that means the window was maximized.
    static func edges(horizontal: Contact, vertical: Contact) -> Gap.Edge {
        var result: Gap.Edge = .none
        switch horizontal {
        case .start: result.insert(.left)
        case .end: result.insert(.right)
        case .both: result.formUnion([.left, .right])
        case .neither: break
        }
        switch vertical {
        case .start: result.insert(.bottom)
        case .end: result.insert(.top)
        case .both: result.formUnion([.bottom, .top])
        case .neither: break
        }
        return result
    }
}
