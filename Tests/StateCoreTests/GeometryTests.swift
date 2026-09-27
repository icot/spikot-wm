import Foundation
import Testing

@testable import StateCore

@Suite("Mode computation")
struct ModeTests {

    @Test("One display splits the primary screen only")
    func laptopOnly() {
        let state = Fixtures.state(displays: Fixtures.laptopOnly)
        state.computeModes()

        // 1512 wide: quarters at 378 and 1134, sixths at 252, 756 and 1260.
        #expect(state.modes["twoColumns"] == [378, 1134])
        #expect(state.modes["threeColumns"] == [252, 756, 1260])
        #expect(state.activeMode == [378, 1134])
    }

    @Test("A second display to the right prepends its midpoint as stack 0")
    func laptopPlusUltrawide() {
        let state = Fixtures.state(displays: Fixtures.laptopPlusUltrawide)
        state.computeModes()

        // The ultrawide sits at x=1512 and is 5120 wide, so its midpoint is 4072.
        #expect(state.modes["twoColumns"] == [4072, 378, 1134])
        #expect(state.modes["threeColumns"] == [4072, 252, 756, 1260])
        #expect(state.activeMode.count == 3, "twoColumns gains a stack for the external display")
    }

    @Test("threeColumns selects the three-way split")
    func threeColumnMode() {
        let state = Fixtures.state(
            config: Config(activeMode: "threeColumns", useCache: false),
            displays: Fixtures.laptopOnly)
        state.computeModes()
        #expect(state.activeMode == [252, 756, 1260])
    }

    @Test("No displays leaves the mode table alone instead of trapping")
    func noDisplays() {
        let state = Fixtures.state(displays: [])
        state.computeModes()
        #expect(state.modes.isEmpty)
        #expect(state.activeMode.isEmpty)
    }
}

@Suite("Window to stack assignment")
struct WindowInColumnTests {
    let mode = [378, 1134]

    @Test("A window is in the stack whose centre it covers")
    func coversCentre() {
        let left = Fixtures.window(number: 1, owner: "A", coordX: 0, width: 756)
        let right = Fixtures.window(number: 2, owner: "B", coordX: 756, width: 756)
        #expect(windowInColumn(window: left, mode: mode) == 0)
        #expect(windowInColumn(window: right, mode: mode) == 1)
    }

    @Test("A window covering no centre belongs to no stack")
    func coversNothing() {
        // Sits between the two centres, touching neither.
        let orphan = Fixtures.window(number: 3, owner: "C", coordX: 400, width: 100)
        #expect(windowInColumn(window: orphan, mode: mode) == nil)
    }

    @Test("The left edge is exclusive and the right edge inclusive")
    func edges() {
        // The test is stackCenter > coordX and stackCenter <= coordX + width, so a window
        // starting exactly on a centre does not claim it, but one ending on it does.
        let startsOnCentre = Fixtures.window(number: 4, owner: "D", coordX: 378, width: 1)
        let endsOnCentre = Fixtures.window(number: 5, owner: "E", coordX: 377, width: 1)
        #expect(windowInColumn(window: startsOnCentre, mode: mode) == nil)
        #expect(windowInColumn(window: endsOnCentre, mode: mode) == 0)
    }

    @Test("Negative coordinates work, for a display left of the primary")
    func negativeOrigin() {
        let onLeftDisplay = Fixtures.window(number: 6, owner: "F", coordX: -1500, width: 1490)
        #expect(windowInColumn(window: onLeftDisplay, mode: [-750, 378, 1134]) == 0)
    }
}

@Suite("Stack partitioning")
struct StackPartitionTests {

    @Test("Windows are grouped per stack, and unassigned ones are dropped")
    func partition() {
        let windows = [
            Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756),
            Fixtures.window(number: 2, owner: "Ghostty", coordX: 756, width: 756),
            Fixtures.window(number: 3, owner: "Firefox", coordX: 756, width: 756),
            Fixtures.window(number: 4, owner: "Orphan", coordX: 400, width: 100),
        ]
        let stacks = stack(windows: windows, mode: [378, 1134])

        #expect(stacks.count == 2)
        #expect(stacks[0].map { $0.kCGWindowOwnerName } == ["Emacs"])
        #expect(stacks[1].map { $0.kCGWindowOwnerName } == ["Ghostty", "Firefox"])
        let assigned = stacks.flatMap { $0 }.count
        #expect(assigned == 3, "the orphan is in no stack")
    }

    @Test("An empty window list yields one empty stack per mode entry")
    func empty() {
        let stacks = stack(windows: [], mode: [378, 1134])
        let allEmpty = stacks.allSatisfy { $0.isEmpty }
        #expect(stacks.count == 2)
        #expect(allEmpty)
    }

    @Test("borders windows are excluded from the computed stacks")
    func excludesBorders() {
        let windows = [
            Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756),
            Fixtures.window(number: 2, owner: "borders", coordX: 0, width: 756),
        ]
        let state = Fixtures.state(windows: windows, displays: Fixtures.laptopOnly)
        state.initialize()
        #expect(state.visibleWindows.map { $0.kCGWindowOwnerName } == ["Emacs"])
    }
}

@Suite("Coordinate spaces")
struct FlipTests {

    @Test("Flipping moves the origin from the bottom-left corner to the top-left one")
    func basics() {
        // The laptop is 982 tall, so a rect sitting on the bottom edge is 982 - height from
        // the top.
        let axis = Geometry.flipAxis(Fixtures.laptopOnly)
        #expect(axis == 982)
        let bottomLeft = CGRect(x: 10, y: 10, width: 100, height: 200)
        let topLeft = Geometry.flipped(bottomLeft, axis: axis)
        #expect(topLeft == CGRect(x: 10, y: 772, width: 100, height: 200))
        #expect(topLeft.size == bottomLeft.size, "only the origin moves")
    }

    @Test("Flipping twice returns the original, which is why there is one function")
    func involution() {
        let axis = Geometry.flipAxis(Fixtures.laptopPlusUltrawide)
        let rect = CGRect(x: 1522, y: -448, width: 5100, height: 1382)
        #expect(Geometry.flipped(Geometry.flipped(rect, axis: axis), axis: axis) == rect)
    }

    @Test("The axis is the primary display's top, not the tallest display's")
    func axisIsPrimary() {
        // The ultrawide is 1440 tall against the laptop's 982, and sits at y = -458 so that
        // the two tops line up at 982. Using the wrong display here is the bug that made
        // placement on the external monitor wrong while looking fine on the laptop.
        #expect(Geometry.flipAxis(Fixtures.laptopPlusUltrawide) == 982)
        let ultrawide = Fixtures.laptopPlusUltrawide[1]
        #expect(ultrawide.frame.maxY == 982)
        // The ultrawide's own top is therefore y = 0 in the flipped space.
        #expect(Geometry.flipped(ultrawide.frame, axis: 982).minY == 0)
    }

    @Test("A symmetric rect on one display flips to itself, which is why this hid for so long")
    func symmetricCase() {
        // 982 tall, a rect from 291 to 691 is centred, so flipping is a no-op. Every rect the
        // old placer produced on the laptop alone was close to this.
        let rect = CGRect(x: 0, y: 291, width: 100, height: 400)
        #expect(Geometry.flipped(rect, axis: 982) == rect)
    }

    @Test("Displays are ordered by position, not by which one is primary")
    func ordering() {
        let rightToLeft = [
            Fixtures.laptopPlusUltrawide[0],
            DisplayInfo(
                frame: CGRect(x: -5120, y: 0, width: 5120, height: 1440),
                visibleFrame: CGRect(x: -5120, y: 0, width: 5120, height: 1402),
                isMain: false),
        ]
        let ordered = Geometry.leftToRight(rightToLeft)
        #expect(ordered.first?.frame.minX == -5120, "the external display is to the left")
        #expect(ordered.last?.isMain == true)
    }
}

@Suite("Gap insets")
struct GapTests {

    @Test("With no shared edge the rect loses a full gap on every side")
    func plainInset() {
        let inset = Gap.apply(to: CGRect(x: 0, y: 0, width: 100, height: 100), size: 10)
        #expect(inset == CGRect(x: 10, y: 10, width: 80, height: 80))
    }

    @Test("A shared edge gets half the gap back, so interior spacing matches the border")
    func sharedEdges() {
        let left = Gap.apply(
            to: CGRect(x: 100, y: 0, width: 100, height: 100), size: 10, sharedEdges: .left)
        #expect(left == CGRect(x: 105, y: 10, width: 85, height: 80))
        let both = Gap.apply(
            to: CGRect(x: 100, y: 0, width: 100, height: 100), size: 10,
            sharedEdges: [.left, .right])
        #expect(both == CGRect(x: 105, y: 10, width: 90, height: 80))
    }

    @Test("One dimension can be left alone")
    func horizontalOnly() {
        let inset = Gap.apply(
            to: CGRect(x: 0, y: 0, width: 100, height: 100), size: 10, dimension: .horizontal)
        #expect(inset == CGRect(x: 10, y: 0, width: 80, height: 100))
    }

    @Test("Rectangle's rule keeps gaps uniform but does not divide the slack evenly")
    func unevenColumns() {
        // The measurement behind the choice in Geometry.layout: three columns of 3440 with a
        // gap of 10 come out 1131.67, 1136.67, 1131.67, because the middle column has two
        // shared edges and gets half a gap back twice. Right for matching Rectangle's thirds,
        // wrong for stacks that are meant to be the same width.
        let width: CGFloat = 3440 / 3
        let columns = (0..<3).map { column in
            var shared: Gap.Edge = .none
            if column > 0 { shared.insert(.left) }
            if column < 2 { shared.insert(.right) }
            return Gap.apply(
                to: CGRect(x: width * CGFloat(column), y: 0, width: width, height: 100),
                size: 10, sharedEdges: shared)
        }
        #expect(abs(columns[0].width - 1131.667) < 0.01)
        #expect(abs(columns[1].width - 1136.667) < 0.01)
        #expect(abs(columns[2].width - 1131.667) < 0.01)
        // Uniform gaps all the same: border, interior, interior, border.
        #expect(abs(columns[0].minX - 10) < 0.01)
        #expect(abs(columns[1].minX - columns[0].maxX - 10) < 0.01)
        #expect(abs(columns[2].minX - columns[1].maxX - 10) < 0.01)
        #expect(abs(3440 - columns[2].maxX - 10) < 0.01)
    }
}

@Suite("Stack placement")
struct StackLayoutTests {

    @Test("Two stacks on one display are equal halves of the visible frame")
    func twoColumnsOneDisplay() {
        let placements = Geometry.layout(
            displays: Fixtures.laptopOnly, centres: [378, 1134], gap: 10)
        #expect(placements.count == 2)
        // (1512 - 3 * 10) / 2 = 741 each.
        #expect(placements[0].frame == CGRect(x: 10, y: 10, width: 741, height: 924))
        #expect(placements[1].frame == CGRect(x: 761, y: 10, width: 741, height: 924))
        #expect(placements[0].frame.width == placements[1].frame.width, "equal stacks")
        // Uniform gaps: border, interior, border.
        #expect(placements[1].frame.minX - placements[0].frame.maxX == 10)
        #expect(1512 - placements[1].frame.maxX == 10)
    }

    @Test("Placement uses the visible frame, so nothing lands under the menu bar")
    func respectsVisibleFrame() {
        let placements = Geometry.layout(
            displays: Fixtures.laptopOnly, centres: [378, 1134], gap: 10)
        // The fixture's visibleFrame is 944 of 982 tall, so the menu bar takes 38 points. In
        // the flipped space the window starts 38 + gap below the top of the screen.
        #expect(placements[0].frame.height == 924, "944 less two gaps")
        #expect(placements[0].axFrame.minY == 48, "38 for the menu bar, 10 for the gap")
        #expect(placements[0].axFrame.height == placements[0].frame.height)
    }

    @Test("With the ultrawide attached, stack 0 goes to it and the rest halve the laptop")
    func multiDisplay() {
        // The bug this replaces: the old placer divided NSScreen.main's width by
        // activeMode.count, and computeModes prepends an entry for the external display, so
        // twoColumns reported three stacks and the laptop was cut into thirds of 490 while
        // stack 0's windows were expected on the ultrawide.
        let placements = Geometry.layout(
            displays: Fixtures.laptopPlusUltrawide, centres: [4072, 378, 1134], gap: 10)
        #expect(placements.count == 3)

        #expect(placements[0].display == 1, "the 5120x1440 display")
        #expect(placements[0].frame == CGRect(x: 1522, y: -448, width: 5100, height: 1382))

        #expect(placements[1].display == 0)
        #expect(placements[2].display == 0)
        #expect(placements[1].frame.width == 741, "half the laptop, not a third")
        #expect(placements[2].frame.width == 741)
        #expect(placements[1].frame.minX == 10)
        #expect(placements[2].frame.minX == 761)
    }

    @Test("The external display's rect converts correctly despite its negative origin")
    func negativeOriginConverts() {
        // The case that is badly wrong without the flip: the ultrawide sits at y = -458, so a
        // rect there has a negative y in AppKit's space and a positive one in the Accessibility
        // API's.
        let placements = Geometry.layout(
            displays: Fixtures.laptopPlusUltrawide, centres: [4072, 378, 1134], gap: 10)
        let ultrawide = placements[0]
        #expect(ultrawide.frame.minY == -448)
        #expect(ultrawide.axFrame.minY == 48, "38 for the menu bar, 10 for the gap")
        #expect(ultrawide.axFrame.minX == ultrawide.frame.minX, "x is the same in both spaces")
    }

    @Test("Three columns leave uniform gaps, with the middle one half a gap wider each side")
    func threeColumns() {
        // 1512 / 3 = 504 raw. Inset by 10 leaves 484; the outer columns get half a gap back
        // once and the middle one twice, so 489, 494, 489. Matching Rectangle here is a
        // deliberate choice over three equal columns of 490.67; see Geometry.layout.
        let placements = Geometry.layout(
            displays: Fixtures.laptopOnly, centres: [252, 756, 1260], gap: 10)
        #expect(placements.map(\.frame.width) == [489, 494, 489])
        #expect(placements[1].frame.minX - placements[0].frame.maxX == 10)
        #expect(placements[2].frame.minX - placements[1].frame.maxX == 10)
        #expect(1512 - placements[2].frame.maxX == 10)
        // Same total either way: 3 columns plus 4 gaps fill the display.
        let covered = placements.map(\.frame.width).reduce(0, +) + 40
        #expect(covered == 1512)
    }

    @Test("A stack lands where Rectangle Pro put the window it is replacing")
    func matchesRectangleOnThisMachine() {
        // Measured with `spikot-wm debug ax` on the 3440x1440 display, on the three windows
        // Rectangle Pro had placed: 1131x1390@(10,40), 1137x1390@(1151,40) and, for Emacs,
        // 1128x1383@(2302,44) after it quantised to character cells. This asserts the first
        // two, in the Accessibility API's coordinates, which is what the placer writes.
        let display = DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 3440, height: 1410),
            isMain: true)
        let placements = Geometry.layout(
            displays: [display], centres: [573, 1720, 2866], gap: 10)
        #expect(placements[0].axFrame.minX == 10)
        #expect(placements[0].axFrame.minY == 40, "30 for the menu bar, 10 for the gap")
        #expect(placements[0].axFrame.height == 1390)
        #expect(Int(placements[0].axFrame.width) == 1131)
        #expect(Int(placements[1].axFrame.minX) == 1151)
        #expect(Int(placements[1].axFrame.width) == 1136, "Rectangle reported 1137 after rounding")
    }

    @Test("A gap of zero leaves the stacks touching and filling the display")
    func noGap() {
        let placements = Geometry.layout(
            displays: Fixtures.laptopOnly, centres: [378, 1134], gap: 0)
        #expect(placements[0].frame == CGRect(x: 0, y: 0, width: 756, height: 944))
        #expect(placements[1].frame.minX == placements[0].frame.maxX)
        #expect(placements[1].frame.maxX == 1512)
    }

    @Test("No displays or no stacks yields nothing rather than trapping")
    func degenerate() {
        #expect(Geometry.layout(displays: [], centres: [378], gap: 10).isEmpty)
        #expect(Geometry.layout(displays: Fixtures.laptopOnly, centres: [], gap: 10).isEmpty)
    }

    @Test("A centre on no display falls back to the nearest rather than dropping the stack")
    func centreOffScreen() {
        // Happens with a cache written while another display was attached. Dropping the stack
        // would renumber every stack after it, which is worse than placing it somewhere.
        let placements = Geometry.layout(
            displays: Fixtures.laptopOnly, centres: [378, 9000], gap: 10)
        #expect(placements.count == 2)
        #expect(placements[1].display == 0)
    }

    @Test("Stacks come back in stack order whatever display they landed on")
    func ordering() {
        let placements = Geometry.layout(
            displays: Fixtures.laptopPlusUltrawide, centres: [4072, 378, 1134], gap: 10)
        #expect(placements.map(\.stack) == [0, 1, 2])
    }

    @Test("State exposes the layout for the current stacks")
    func throughState() {
        let state = Fixtures.state(displays: Fixtures.laptopPlusUltrawide)
        state.initialize()
        let placements = state.stackLayout()
        #expect(placements.count == state.activeMode.count)
        #expect(placements[0].display == 1, "twoColumns puts stack 0 on the external display")
    }
}

@Suite("Placement actions")
struct PlacementActionTests {

    @Test("A bare number is a stack index, so place 1 means what spikot-placer 1 meant")
    func parseStack() throws {
        #expect(try PlacementAction.parse("1") == .stack(1))
        #expect(try PlacementAction.parse(" 0 ") == .stack(0))
        #expect(try PlacementAction.parse("1").name == "stack 1")
    }

    @Test("A negative index and a word that is not an action are separate errors")
    func parseFailures() {
        #expect(throws: PlacementError.negativeStack(-1)) { try PlacementAction.parse("-1") }
        #expect(throws: PlacementError.self) { try PlacementAction.parse("sideways") }
    }
}

@Suite("Placing windows")
struct PlaceTests {

    /// A state with one window, whose placement can be checked without the window server.
    private func state(stacks: String = "twoColumns") -> State {
        Fixtures.state(
            config: Config(activeMode: stacks, useCache: false),
            windows: [Fixtures.window(number: 7, owner: "Safari", coordX: 0, width: 400)],
            displays: Fixtures.laptopOnly,
            frontmostPID: 100)
    }

    @Test("A stack index outside the layout is an error, not a trap")
    func indexGuarded() throws {
        // spikot-placer accepted 3 and 4 as arguments while indexing stacks[targetStack]
        // unguarded, so `spikot-placer 4` on a two-stack layout crashed.
        let state = self.state()
        state.initialize()
        #expect(throws: PlacementError.noPlacement(stack: 4, stacks: 2)) {
            try state.place(.stack(4), windowNumber: 7)
        }
        #expect(throws: PlacementError.noPlacement(stack: 2, stacks: 2)) {
            try state.place(.stack(2), windowNumber: 7)
        }
    }

    @Test("An unknown window number is reported rather than silently doing nothing")
    func unknownWindow() throws {
        let state = self.state()
        state.initialize()
        #expect(throws: StackError.unknownWindow(99)) {
            try state.place(.stack(0), windowNumber: 99)
        }
    }

    @Test("Placing rewrites stack membership, so the next run does not undo it")
    func membershipMoves() throws {
        // Stack membership is derived from window position and then merged with the cache, so
        // without this the window would snap back to the stack its coordinates imply.
        let state = self.state()
        state.initialize()
        #expect(state.stacks[0].contains { $0.kCGWindowNumber == 7 })
        state.assign(state.visibleWindows[0], toStack: 1)
        #expect(state.stacks[0].isEmpty)
        #expect(state.stacks[1].map(\.kCGWindowNumber) == [7])
    }

    @Test("Assigning to a stack that does not exist logs instead of trapping")
    func assignGuarded() throws {
        let state = self.state()
        state.initialize()
        state.assign(state.visibleWindows[0], toStack: 9)
        // The window is removed from its old stack either way; what matters is not crashing.
        #expect(state.stacks.count == 2)
    }

    @Test("With no displays there is nowhere to place anything")
    func noDisplays() throws {
        let state = Fixtures.state(
            windows: [Fixtures.window(number: 7, owner: "Safari", coordX: 0, width: 400)],
            displays: [])
        state.initialize()
        #expect(throws: PlacementError.noDisplays) {
            try state.place(.stack(0), windowNumber: 7)
        }
    }

    @Test("The frontmost path needs a frontmost application")
    func frontmostMissing() throws {
        let state = Fixtures.state(
            windows: [Fixtures.window(number: 7, owner: "Safari", coordX: 0, width: 400)],
            displays: Fixtures.laptopOnly,
            frontmostPID: nil)
        state.initialize()
        #expect(throws: StackError.noCurrentStack) { try state.placeFrontmost(.stack(0)) }
    }
}

@Suite("Halves and maximize")
struct HalvesTests {
    /// The laptop fixture's visible frame: 1512x944 at the origin.
    private let visible = Fixtures.laptopOnly[0].visibleFrame

    @Test("Maximize is the whole visible frame, inset by the gap")
    func maximize() {
        let rect = Placement.rect(for: .maximize, in: visible, gap: 10)
        #expect(rect == CGRect(x: 10, y: 10, width: 1492, height: 924))
        // Nothing is shared, so every side gets a full gap.
        #expect(rect.minX - visible.minX == 10)
        #expect(visible.maxX - rect.maxX == 10)
    }

    @Test("Maximize with no gap is exactly the visible frame")
    func maximizeNoGap() {
        #expect(Placement.rect(for: .maximize, in: visible, gap: 0) == visible)
    }

    @Test("The halves meet in the middle with one gap between them")
    func halvesMeet() {
        let left = Placement.rect(for: .leftHalf, in: visible, gap: 10)
        let right = Placement.rect(for: .rightHalf, in: visible, gap: 10)
        // 1512 / 2 = 756 raw; inset to 736 and half a gap back on the shared edge.
        #expect(left == CGRect(x: 10, y: 10, width: 741, height: 924))
        #expect(right == CGRect(x: 761, y: 10, width: 741, height: 924))
        #expect(right.minX - left.maxX == 10, "one gap between them, as at the screen edge")
        #expect(left.width == right.width)
        // Identical to two columnar stacks, which is why the two models agree for halves.
        let stacks = Geometry.layout(displays: Fixtures.laptopOnly, centres: [378, 1134], gap: 10)
        #expect(stacks[0].frame == left)
        #expect(stacks[1].frame == right)
    }

    @Test("Top and bottom halves split the other axis, bottom-left origin and all")
    func verticalHalves() {
        let top = Placement.rect(for: .topHalf, in: visible, gap: 10)
        let bottom = Placement.rect(for: .bottomHalf, in: visible, gap: 10)
        // 944 / 2 = 472 raw at y = 472; inset leaves 452 at y = 482, and half a gap back on
        // the shared bottom edge gives 457 at y = 477.
        #expect(top == CGRect(x: 10, y: 477, width: 1492, height: 457))
        #expect(bottom == CGRect(x: 10, y: 10, width: 1492, height: 457))
        #expect(top.minY - bottom.maxY == 10)
        #expect(top.maxY == visible.maxY - 10, "the top half is against the top of the screen")
    }

    @Test("A repeated press cycles a half, two thirds, a third, then back")
    func cycling() {
        // Rectangle's default: subsequentExecutionMode is unset, which reads as .resize, and the
        // cycle set [oneHalf, twoThirds, oneThird] is ordered first-then-larger-then-smaller.
        let widths = (0..<4).map { repeats in
            Placement.rect(for: .leftHalf, in: visible, gap: 0, repeats: repeats).width
        }
        #expect(widths[0] == 756, "half of 1512")
        #expect(widths[1] == 1008, "two thirds")
        #expect(widths[2] == 504, "one third")
        #expect(widths[3] == widths[0], "the cycle wraps")
    }

    @Test("Maximize does not cycle, because there is nothing to cycle through")
    func maximizeDoesNotCycle() {
        let first = Placement.rect(for: .maximize, in: visible, gap: 10)
        let second = Placement.rect(for: .maximize, in: visible, gap: 10, repeats: 1)
        #expect(first == second)
    }

    @Test("Dimensions round down, with Rectangle's tolerance")
    func rounding() {
        // 3440 / 3 = 1146.666…, and two thirds of it is 2293.333…, so flooring matters. The
        // tolerance stops a value a whisker under an integer losing a whole pixel.
        #expect(Placement.floorDimension(1146.6666) == 1146)
        #expect(Placement.floorDimension(1146.99999) == 1147, "0.0001 of tolerance")
        #expect(Placement.floorDimension(1147) == 1147)
    }

    @Test("Repeat counting only continues while the same action is pressed")
    func lastActionBookkeeping() {
        #expect(LastAction.repeats(nil, for: .leftHalf) == 0)
        let first = LastAction.advancing(nil, with: .leftHalf)
        #expect(first == LastAction(action: "left-half", count: 1))
        #expect(LastAction.repeats(first, for: .leftHalf) == 1)
        // A different action resets, so left-half then right-half gives a half, not two thirds.
        #expect(LastAction.repeats(first, for: .rightHalf) == 0)
        let second = LastAction.advancing(first, with: .leftHalf)
        #expect(second.count == 2)
        #expect(LastAction.advancing(second, with: .rightHalf).count == 1)
    }

    @Test("Every action name parses, in both spellings")
    func parsing() throws {
        #expect(try PlacementAction.parse("left-half") == .leftHalf)
        #expect(try PlacementAction.parse("leftHalf") == .leftHalf, "Rectangle's own spelling")
        #expect(try PlacementAction.parse("MAXIMIZE") == .maximize)
        #expect(try PlacementAction.parse("bottom-half") == .bottomHalf)
        #expect(throws: PlacementError.self) { try PlacementAction.parse("left-quarter") }
    }

    @Test("An action applies to the display the window is on, not the main one")
    func perDisplay() {
        // A window on the ultrawide, in the Accessibility API's coordinates: the ultrawide's top
        // is y = 0 there, so a window at y = 100 on it is well clear of the laptop.
        let onUltrawide = CGRect(x: 3000, y: 100, width: 800, height: 600)
        #expect(
            Geometry.display(containingWindow: onUltrawide, in: Fixtures.laptopPlusUltrawide) == 1)
        let onLaptop = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(
            Geometry.display(containingWindow: onLaptop, in: Fixtures.laptopPlusUltrawide) == 0)
    }

    @Test("A window straddling two displays belongs to the one showing most of it")
    func straddling() {
        // Mostly on the laptop, 1200 of its 1400 points.
        let straddling = CGRect(x: 300, y: 100, width: 1400, height: 300)
        #expect(
            Geometry.display(containingWindow: straddling, in: Fixtures.laptopPlusUltrawide) == 0)
    }
}

@Suite("Thirds")
struct ThirdsTests {
    /// The ultrawide's visible frame, where the rounding is worst: 5120 / 3 = 1706.67.
    private let ultrawide = Fixtures.laptopPlusUltrawide[1].visibleFrame

    @Test("The three thirds cover the display with only the configured gaps between them")
    func thirdsTile() {
        let first = Placement.rect(for: .firstThird, in: ultrawide, gap: 10)
        let centre = Placement.rect(for: .centerThird, in: ultrawide, gap: 10)
        let last = Placement.rect(for: .lastThird, in: ultrawide, gap: 10)

        #expect(first.minX == ultrawide.minX + 10, "a full gap at the screen edge")
        #expect(abs(ultrawide.maxX - last.maxX - 10) < 0.01)
        #expect(first.height == ultrawide.height - 20, "thirds span the other axis")
        // The gaps are not equal, and this is Rectangle's arithmetic rather than a defect here.
        // 5120 / 3 = 1706.67: the first and last thirds are floored to 1706 while the centre
        // keeps the exact width, so the space left over lands between the centre and the last.
        #expect(centre.minX - first.maxX == 10, "exactly one gap on the left of the centre")
        #expect(abs(last.minX - centre.maxX - 10 - 4.0 / 3) < 0.01, "and 1.33 too much on the right")
    }

    @Test("Rectangle's centre-third asymmetry is reproduced rather than tidied up")
    func centreThirdAsymmetry() {
        // CenterThirdCalculation floors the origin and leaves the size exact. Keeping the quirk
        // is what makes the frames match Rectangle's to the pixel.
        let display = CGRect(x: 0, y: 0, width: 3440, height: 1410)
        let centre = Placement.rect(for: .centerThird, in: display, gap: 0)
        #expect(centre.minX == 1146, "floor(3440 / 3)")
        #expect(abs(centre.width - 3440.0 / 3) < 0.001, "the exact third, not floored")
    }

    @Test("Two-thirds actions take two thirds, from the correct side")
    func twoThirds() {
        let first = Placement.rect(for: .firstTwoThirds, in: ultrawide, gap: 0)
        let last = Placement.rect(for: .lastTwoThirds, in: ultrawide, gap: 0)
        #expect(first.width == 3413, "floor(5120 * 2 / 3)")
        #expect(first.minX == ultrawide.minX)
        #expect(last.width == first.width)
        #expect(last.maxX == ultrawide.maxX)
        // A first third and a last two-thirds nearly fill the display: both are floored, so
        // 1706 + 3413 leaves one pixel of the 5120 unclaimed. Rectangle leaves it too.
        let third = Placement.rect(for: .firstThird, in: ultrawide, gap: 0)
        #expect(third.width + last.width == ultrawide.width - 1)
    }

    @Test("Thirds take a gap on the edges they share and a full gap at the screen edge")
    func thirdGaps() {
        let display = CGRect(x: 0, y: 0, width: 300, height: 100)
        // 100 wide raw. First third: inset to 80, half a gap back on the right, so 85 at x=10.
        #expect(Placement.rect(for: .firstThird, in: display, gap: 10)
            == CGRect(x: 10, y: 10, width: 85, height: 80))
        // Centre third: both sides shared, so 90 at x = 105.
        #expect(Placement.rect(for: .centerThird, in: display, gap: 10)
            == CGRect(x: 105, y: 10, width: 90, height: 80))
        // Last third: shared left, 85 at x = 205.
        #expect(Placement.rect(for: .lastThird, in: display, gap: 10)
            == CGRect(x: 205, y: 10, width: 85, height: 80))
    }

    @Test("On a portrait display the thirds split the other axis")
    func portrait() {
        // Ported from Rectangle's portraitRect and never observed: no portrait display has been
        // attached to this machine.
        let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let first = Placement.rect(for: .firstThird, in: portrait, gap: 0)
        let last = Placement.rect(for: .lastThird, in: portrait, gap: 0)
        #expect(first.height == 640)
        #expect(first.maxY == portrait.maxY, "the first third is the top one")
        #expect(last.minY == portrait.minY, "the last third is the bottom one")
        #expect(first.width == portrait.width)
    }

    @Test("Thirds do not cycle on a repeat")
    func noCycling() {
        let first = Placement.rect(for: .firstThird, in: ultrawide, gap: 10)
        #expect(Placement.rect(for: .firstThird, in: ultrawide, gap: 10, repeats: 2) == first)
    }

    @Test("Every third parses, including Rectangle's names for them")
    func parsing() throws {
        #expect(try PlacementAction.parse("first-third") == .firstThird)
        #expect(try PlacementAction.parse("left-third") == .firstThird, "the same rect")
        #expect(try PlacementAction.parse("centerThird") == .centerThird)
        #expect(try PlacementAction.parse("last-two-thirds") == .lastTwoThirds)
    }
}

@Suite("Moving between displays")
struct DisplayTransferTests {
    private let laptop = Fixtures.laptopPlusUltrawide[0].visibleFrame
    private let ultrawide = Fixtures.laptopPlusUltrawide[1].visibleFrame
    private let tolerance = DisplayTransfer.edgeTolerance(gap: 10)

    @Test("A maximized window stays maximized, and says so")
    func maximized() {
        // Against all four edges, which is how State.place recognises it and maximizes on the
        // destination instead of stretching the old rect.
        let moved = DisplayTransfer.transferredRect(
            window: laptop, source: laptop, destination: ultrawide, tolerance: tolerance)
        #expect(moved.sharedEdges == .all)
        #expect(moved.rect == ultrawide)
    }

    @Test("A left half stays a left half, full height, at the destination's size")
    func leftHalfFollows() {
        let half = Placement.rect(for: .leftHalf, in: laptop, gap: 10)
        let moved = DisplayTransfer.transferredRect(
            window: half, source: laptop, destination: ultrawide, tolerance: tolerance)
        // Against the left, top and bottom edges, so it spans the destination vertically and
        // keeps its width against the left edge.
        #expect(moved.rect.minX == ultrawide.minX + 10, "the 10 point inset carries over")
        #expect(moved.rect.width == half.width, "the width is kept, not rescaled")
        #expect(moved.rect.height == ultrawide.height - 20, "still full height, gaps and all")
    }

    @Test("A window against neither edge keeps its size and its relative position")
    func floating() {
        // Centred on the laptop's visible frame, so it should arrive centred on the ultrawide.
        let floating = CGRect(x: 556, y: 322, width: 400, height: 300)
        let moved = DisplayTransfer.transferredRect(
            window: floating, source: laptop, destination: ultrawide, tolerance: tolerance)
        #expect(moved.sharedEdges == .none)
        #expect(moved.rect.size == floating.size)
        #expect(abs(moved.rect.midX - ultrawide.midX) < 1)
        #expect(abs(moved.rect.midY - ultrawide.midY) < 1)
    }

    @Test("A window too big for the destination is cut down to fit")
    func tooBig() {
        let huge = CGRect(x: 1600, y: -400, width: 4000, height: 1300)
        let moved = DisplayTransfer.transferredRect(
            window: huge, source: ultrawide, destination: laptop, tolerance: tolerance)
        #expect(moved.rect.width <= laptop.width)
        #expect(moved.rect.height <= laptop.height)
    }

    @Test("Next and previous follow screen position and wrap around")
    func adjacency() {
        let displays = Fixtures.laptopPlusUltrawide
        // The laptop is at x=0 and the ultrawide at x=1512, so next from the laptop is the
        // ultrawide and next from the ultrawide wraps back.
        #expect(Geometry.adjacentDisplay(to: 0, in: displays, forward: true) == 1)
        #expect(Geometry.adjacentDisplay(to: 1, in: displays, forward: true) == 0)
        #expect(Geometry.adjacentDisplay(to: 0, in: displays, forward: false) == 1)
        #expect(Geometry.adjacentDisplay(to: 1, in: displays, forward: false) == 0)
    }

    @Test("With one display there is no next one, rather than a move onto itself")
    func singleDisplay() {
        #expect(Geometry.adjacentDisplay(to: 0, in: Fixtures.laptopOnly, forward: true) == nil)
    }

    @Test("A display move reports the single-display case instead of doing nothing")
    func placeRefusesWithOneDisplay() throws {
        let state = Fixtures.state(
            windows: [Fixtures.window(number: 7, owner: "Safari", coordX: 0, width: 400)],
            displays: Fixtures.laptopOnly)
        state.initialize()
        #expect(throws: PlacementError.singleDisplay) {
            try state.place(.nextDisplay, windowNumber: 7)
        }
    }

    @Test("The edge tolerance grows with the gap, since nothing is ever flush with gaps on")
    func tolerance_() {
        #expect(DisplayTransfer.edgeTolerance(gap: 0) == 4)
        #expect(DisplayTransfer.edgeTolerance(gap: 10) == 14)
    }

    @Test("Orientation changes are only landscape to portrait or back")
    func orientation() {
        let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        #expect(DisplayTransfer.changesOrientation(from: laptop, to: portrait))
        #expect(DisplayTransfer.changesOrientation(from: portrait, to: laptop))
        #expect(!DisplayTransfer.changesOrientation(from: laptop, to: ultrawide))
        // A square display is neither, so it never counts.
        let square = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        #expect(!DisplayTransfer.changesOrientation(from: laptop, to: square))
    }

    @Test("A three-edge window moving to a portrait display is centred, not stretched")
    func threeEdgesToPortrait() {
        // A left half spans the vertical axis and is against one horizontal edge. Following both
        // vertical edges onto a portrait display would make it a sliver 1920 points tall.
        let portrait = CGRect(x: 2000, y: 0, width: 1080, height: 1920)
        let half = Placement.rect(for: .leftHalf, in: laptop, gap: 0)
        let moved = DisplayTransfer.transferredRect(
            window: half, source: laptop, destination: portrait, tolerance: tolerance)
        #expect(moved.rect.height == half.height, "the height is kept")
        #expect(abs(moved.rect.midY - portrait.midY) < 1, "and centred on the long axis")
    }
}
