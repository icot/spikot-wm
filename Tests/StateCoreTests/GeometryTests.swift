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
