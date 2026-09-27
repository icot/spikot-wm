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
        case .maximize, .stack:
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
