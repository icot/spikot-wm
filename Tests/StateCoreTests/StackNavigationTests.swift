import Foundation
import Testing

@testable import StateCore

// Regression tests for spikot-win-yeh.5. These could not be written before: the clamp in
// switchStack compared against `config.activeMode.count`, the character count of the mode
// *name* ("twoColumns" is 10), so it never fired and `stacks[targetStack].first!` trapped.
// A trap takes the whole test process down, so withKnownIssue could not have covered it.

@Suite("Current stack")
struct CurrentStackTests {
    let emacs = Fixtures.window(number: 1, owner: "Emacs", pid: 10, coordX: 0, width: 756)
    let ghostty = Fixtures.window(number: 2, owner: "Ghostty", pid: 20, coordX: 756, width: 756)

    @Test("Reports the stack holding the frontmost window")
    func findsStack() {
        let state = Fixtures.state(
            windows: [emacs, ghostty], displays: Fixtures.laptopOnly, frontmostPID: 20)
        state.initialize()
        #expect(state.currentStack() == 1)
    }

    @Test("Nil when nothing is frontmost")
    func noFrontmost() {
        let state = Fixtures.state(
            windows: [emacs], displays: Fixtures.laptopOnly, frontmostPID: nil)
        state.initialize()
        #expect(state.currentStack() == nil)
    }

    @Test("Nil when the frontmost process has no managed window, instead of trapping")
    func frontmostHasNoWindow() {
        // The old implementation force-unwrapped the lookup and crashed here. This is
        // Finder with every window closed, or a full-screen app on another Space.
        let state = Fixtures.state(
            windows: [emacs], displays: Fixtures.laptopOnly, frontmostPID: 999)
        state.initialize()
        #expect(state.currentStack() == nil)
    }

    @Test("Nil when the frontmost window covers no stack centre")
    func windowCoversNoCentre() {
        let orphan = Fixtures.window(number: 3, owner: "Orphan", pid: 30, coordX: 400, width: 100)
        let state = Fixtures.state(
            windows: [orphan], displays: Fixtures.laptopOnly, frontmostPID: 30)
        state.initialize()
        #expect(state.currentStack() == nil)
    }
}

@Suite("Switch stack")
struct SwitchStackTests {
    /// Two stacks, one window each, Ghostty frontmost in stack 1.
    private func twoStacks(frontmostPID: Int32 = 20) -> State {
        let state = Fixtures.state(
            windows: [
                Fixtures.window(number: 1, owner: "Emacs", pid: 10, coordX: 0, width: 756),
                Fixtures.window(number: 2, owner: "Ghostty", pid: 20, coordX: 756, width: 756),
            ],
            displays: Fixtures.laptopOnly,
            frontmostPID: frontmostPID)
        state.initialize()
        return state
    }

    @Test("An absolute index beyond the layout is an error, not a trap")
    func absoluteOutOfRange() {
        // `spikot-wm focus 4` on a two-stack layout. The CLI's validate() allows 0-4
        // regardless of how many stacks exist, so this has to be caught here.
        #expect(throws: StackError.self) { try twoStacks().switchStack(toStack: "4") }
        #expect(throws: StackError.self) { try twoStacks().switchStack(toStack: "2") }
    }

    @Test("A valid absolute index is accepted")
    func absoluteInRange() throws {
        try twoStacks().switchStack(toStack: "0")
        try twoStacks().switchStack(toStack: "1")
    }

    @Test("Relative moves wrap in both directions")
    func relativeWraps() throws {
        // Six moves left from stack 1 across two stacks: none may throw, which is what
        // "wraps cleanly" means. A broken clamp would run off the end.
        let state = twoStacks()
        for _ in 0..<6 {
            try state.switchStack(toStack: "left")
        }
        for _ in 0..<6 {
            try state.switchStack(toStack: "right")
        }
    }

    @Test("An unrecognised target is an error")
    func unknownTarget() {
        #expect(throws: StackError.self) { try twoStacks().switchStack(toStack: "sideways") }
    }

    @Test("An empty target stack is an error rather than a force-unwrap")
    func emptyTarget() {
        // Only stack 1 is occupied, so moving to stack 0 has nothing to focus.
        let state = Fixtures.state(
            windows: [
                Fixtures.window(number: 2, owner: "Ghostty", pid: 20, coordX: 756, width: 756)
            ],
            displays: Fixtures.laptopOnly,
            frontmostPID: 20)
        state.initialize()
        #expect(throws: StackError.self) { try state.switchStack(toStack: "0") }
    }

    @Test("A relative move with no current stack is an error")
    func relativeWithoutCurrentStack() {
        #expect(throws: StackError.self) { try twoStacks(frontmostPID: 999).switchStack(toStack: "left") }
    }
}

@Suite("Rotate stack")
struct RotateStackTests {
    /// Three Ghostty windows in stack 1, all owned by pid 20.
    private func threeInOneStack() -> State {
        let state = Fixtures.state(
            windows: [
                Fixtures.window(number: 1, owner: "A", pid: 20, coordX: 756, width: 756),
                Fixtures.window(number: 2, owner: "B", pid: 20, coordX: 756, width: 756),
                Fixtures.window(number: 3, owner: "C", pid: 20, coordX: 756, width: 756),
            ],
            displays: Fixtures.laptopOnly,
            frontmostPID: 20)
        state.initialize()
        return state
    }

    @Test("up moves the last window to the front")
    func rotateUp() throws {
        let state = threeInOneStack()
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["A", "B", "C"])
        try state.rotateStack(direction: "up")
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["C", "A", "B"])
    }

    @Test("down moves the first window to the back")
    func rotateDown() throws {
        let state = threeInOneStack()
        try state.rotateStack(direction: "down")
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["B", "C", "A"])
    }

    @Test("Three ups return to the starting order")
    func rotateUpFullCycle() throws {
        let state = threeInOneStack()
        for _ in 0..<3 { try state.rotateStack(direction: "up") }
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["A", "B", "C"])
    }

    @Test("up then down is a no-op")
    func upThenDown() throws {
        let state = threeInOneStack()
        try state.rotateStack(direction: "up")
        try state.rotateStack(direction: "down")
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["A", "B", "C"])
    }

    @Test("A single-window stack is left alone without erroring")
    func singleWindow() throws {
        let state = Fixtures.state(
            windows: [Fixtures.window(number: 1, owner: "A", pid: 20, coordX: 756, width: 756)],
            displays: Fixtures.laptopOnly,
            frontmostPID: 20)
        state.initialize()
        try state.rotateStack(direction: "up")
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["A"])
    }

    @Test("An unrecognised direction is an error")
    func unknownDirection() {
        #expect(throws: StackError.self) { try threeInOneStack().rotateStack(direction: "sideways") }
    }

    @Test("Rotating with no current stack is an error")
    func noCurrentStack() {
        let state = Fixtures.state(
            windows: [Fixtures.window(number: 1, owner: "A", pid: 20, coordX: 756, width: 756)],
            displays: Fixtures.laptopOnly,
            frontmostPID: 999)
        state.initialize()
        #expect(throws: StackError.self) { try state.rotateStack(direction: "up") }
    }
}
