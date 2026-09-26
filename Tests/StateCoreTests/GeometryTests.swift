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
