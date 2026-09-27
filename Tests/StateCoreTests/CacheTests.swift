import Foundation
import Testing

@testable import StateCore

@Suite("Cache round-trip")
struct CacheRoundTripTests {

    @Test("A shorter snapshot replaces the file rather than leaving the old tail")
    func shorterWriteTruncates() throws {
        // Regression test for spikot-win-yeh.2. flushCurrentState used to open the file
        // with FileHandle(forWritingTo:), which seeks to 0 without truncating, so a
        // shorter payload left trailing bytes of the previous, longer write. The live
        // cache had 3776 bytes with valid JSON ending at 2036.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-truncate-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileStateStore(url: url)

        let many = (1...20).map {
            Fixtures.window(number: $0, owner: "App\($0)", coordX: 0, width: 756)
        }
        try store.save(snapshot(windows: many))
        let bigSize = try Data(contentsOf: url).count

        try store.save(snapshot(windows: [many[0]]))
        let smallData = try Data(contentsOf: url)

        #expect(smallData.count < bigSize, "the file shrank")
        // The real assertion: nothing follows the JSON.
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode(StateSnapshot.self, from: smallData)
        }
    }

    @Test("Saving then loading returns the same snapshot")
    func roundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-roundtrip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileStateStore(url: url)

        let original = snapshot(windows: [
            Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        ])
        try store.save(original)
        #expect(try store.load() == original)
    }

    @Test("A missing cache is nil, not an error")
    func missingCache() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-absent-\(UUID().uuidString).json")
        #expect(try FileStateStore(url: url).load() == nil)
    }

    @Test("A corrupt cache throws instead of being silently ignored")
    func corruptCache() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // Exactly the shape the live cache had: valid JSON followed by a fragment.
        try Data(#"{"modes":{}}{"stray":1}"#.utf8).write(to: url)
        #expect(throws: (any Error).self) { try FileStateStore(url: url).load() }
    }

    @Test("State reports a corrupt cache as nil so startup continues")
    func stateDiscardsCorruptCache() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spikot-discard-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)

        let state = Fixtures.state(store: FileStateStore(url: url))
        #expect(state.loadCachedState() == nil)
    }

    private func snapshot(windows: [Window]) -> StateSnapshot {
        StateSnapshot(
            modes: ["twoColumns": [378, 1134]],
            activeMode: [378, 1134],
            visibleWindows: windows,
            stacks: [windows, []],
            config: Config())
    }
}

@Suite("Cache merge")
struct CacheMergeTests {

    /// Stack membership set by an earlier run must survive, which is the feature
    /// README.md:31-33 advertises and which did not work until spikot-win-yeh.2.
    @Test("Cached membership wins over the positional guess")
    func membershipSurvives() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        let ghostty = Fixtures.window(number: 2, owner: "Ghostty", coordX: 756, width: 756)

        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134], "threeColumns": [252, 756, 1260]],
            activeMode: [378, 1134],
            visibleWindows: [emacs, ghostty],
            stacks: [[emacs], [ghostty]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs, ghostty],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        #expect(state.stacks[0].map { $0.kCGWindowOwnerName } == ["Emacs"])
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["Ghostty"])
    }

    @Test("A new window is added without disturbing the others")
    func newWindow() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        let ghostty = Fixtures.window(number: 2, owner: "Ghostty", coordX: 756, width: 756)
        let firefox = Fixtures.window(number: 3, owner: "Firefox", coordX: 756, width: 756)

        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134], "threeColumns": [252, 756, 1260]],
            activeMode: [378, 1134],
            visibleWindows: [emacs, ghostty],
            stacks: [[emacs], [ghostty]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs, ghostty, firefox],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        #expect(state.stacks[0].map { $0.kCGWindowOwnerName } == ["Emacs"])
        #expect(Set(state.stacks[1].map { $0.kCGWindowOwnerName }) == ["Ghostty", "Firefox"])
    }

    // Regression tests for spikot-win-yeh.6, fixed in v0.4.3. removeClosedWindows kept
    // the closed window instead of dropping it, and rebuilt newStacks[id] from the cached
    // stacks on every iteration of the outer loop, so the second closed window undid the
    // first one's removal.

    @Test("One closed window is dropped from its stack")
    func oneClosedWindow() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        let ghostty = Fixtures.window(number: 2, owner: "Ghostty", coordX: 756, width: 756)
        let closed = Fixtures.window(number: 99, owner: "Gone", coordX: 756, width: 756)

        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134], "threeColumns": [252, 756, 1260]],
            activeMode: [378, 1134],
            visibleWindows: [emacs, ghostty, closed],
            stacks: [[emacs], [ghostty, closed]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs, ghostty],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        let names = state.stacks.flatMap { $0 }.map { $0.kCGWindowOwnerName }
        #expect(!names.contains("Gone"))
        #expect(state.stacks[0].map { $0.kCGWindowOwnerName } == ["Emacs"])
        #expect(state.stacks[1].map { $0.kCGWindowOwnerName } == ["Ghostty"])
    }

    @Test("Two closed windows are both dropped")
    func twoClosedWindows() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        let goneA = Fixtures.window(number: 98, owner: "GoneA", coordX: 0, width: 756)
        let goneB = Fixtures.window(number: 99, owner: "GoneB", coordX: 756, width: 756)

        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134], "threeColumns": [252, 756, 1260]],
            activeMode: [378, 1134],
            visibleWindows: [emacs, goneA, goneB],
            stacks: [[emacs, goneA], [goneB]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        let names = state.stacks.flatMap { $0 }.map { $0.kCGWindowOwnerName }
        #expect(!names.contains("GoneA"))
        #expect(!names.contains("GoneB"))
        #expect(names == ["Emacs"])
    }

    @Test("A cache from a different display layout is discarded")
    func layoutChangeInvalidatesCache() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        // Cached under the two-display layout, loaded under the one-display layout.
        let cached = StateSnapshot(
            modes: ["twoColumns": [4072, 378, 1134]],
            activeMode: [4072, 378, 1134],
            visibleWindows: [emacs],
            stacks: [[], [emacs], []],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs],
            displays: Fixtures.laptopOnly,
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        #expect(state.stacks.count == 2, "falls back to the freshly computed two stacks")
    }

    @Test("useCache false ignores a present cache")
    func cacheDisabled() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", coordX: 0, width: 756)
        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134]],
            activeMode: [378, 1134],
            visibleWindows: [emacs],
            stacks: [[], [emacs]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: false),
            windows: [emacs],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        #expect(state.stacks[0].map { $0.kCGWindowOwnerName } == ["Emacs"], "positional, not cached")
    }
}

@Suite("Moved windows")
struct MovedWindowTests {

    /// Regression test for the duplicate found through the menu bar item: one Ghostty
    /// window (9607) appeared under both Stack 0 and Stack 1.
    ///
    /// `Window` is Equatable over every field, `kCGWindowBounds` included, so a window that
    /// has moved is not `==` to its cached copy. `reshuffleMovedWindows` inserted the fresh
    /// copy and then searched the other stacks for that same fresh value, which never
    /// matched the stale copy sitting there with the old bounds.
    @Test("A window that moved between stacks ends up in exactly one")
    func movedWindowIsNotDuplicated() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", pid: 10, coordX: 0, width: 756)
        // Cached in stack 1 at its old position.
        let ghosttyBefore = Fixtures.window(
            number: 2, owner: "Ghostty", pid: 20, coordX: 756, width: 756)
        // Now in stack 0, and resized, so it is not == to the cached copy.
        let ghosttyAfter = Fixtures.window(
            number: 2, owner: "Ghostty", pid: 20, coordX: 0, width: 700, height: 900)

        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134], "threeColumns": [252, 756, 1260]],
            activeMode: [378, 1134],
            visibleWindows: [emacs, ghosttyBefore],
            stacks: [[emacs], [ghosttyBefore]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs, ghosttyAfter],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        let placements = state.stacks.enumerated().filter { _, stack in
            stack.contains { $0.kCGWindowNumber == 2 }
        }.map(\.offset)
        #expect(placements.count == 1, "window 2 is in stacks \(placements)")
    }

    @Test("No window number appears twice anywhere in the stacks")
    func noDuplicateWindowNumbers() {
        let emacs = Fixtures.window(number: 1, owner: "Emacs", pid: 10, coordX: 0, width: 756)
        let movedBefore = Fixtures.window(number: 2, owner: "Ghostty", pid: 20, coordX: 756, width: 756)
        let movedAfter = Fixtures.window(number: 2, owner: "Ghostty", pid: 20, coordX: 10, width: 740)

        let cached = StateSnapshot(
            modes: ["twoColumns": [378, 1134], "threeColumns": [252, 756, 1260]],
            activeMode: [378, 1134],
            visibleWindows: [emacs, movedBefore],
            stacks: [[emacs], [movedBefore]],
            config: Config())

        let state = Fixtures.state(
            config: Config(useCache: true),
            windows: [emacs, movedAfter],
            store: InMemoryStateStore(initial: cached))
        state.initialize()

        let numbers = state.stacks.flatMap { $0 }.map { $0.kCGWindowNumber }
        #expect(numbers.count == Set(numbers).count, "duplicated window numbers in \(numbers)")
    }
}
