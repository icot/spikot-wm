import Foundation
import Testing

@testable import StateCore

@Suite("List formats")
struct ListingTests {
    /// Two managed windows plus one from an ignored application.
    private func state() -> State {
        let result = Fixtures.state(
            windows: [
                Fixtures.window(
                    number: 9607, owner: "Ghostty", pid: 29899, coordX: 0, width: 756,
                    title: "spikot-win"),
                Fixtures.window(
                    number: 116, owner: "Emacs", pid: 2396, coordX: 756, width: 756,
                    title: "CLAUDE.md"),
                Fixtures.window(number: 5, owner: "borders", pid: 999, coordX: 0, width: 756),
            ],
            displays: Fixtures.laptopOnly)
        result.initialize()
        return result
    }

    @Test("legacy keeps the window number in field 1 and the pid in field 3")
    func legacyFieldOrder() throws {
        // ~/.local/bin/mylauncher splits on "|" and passed field 3 to `focus --window`,
        // which activated an application by pid. No binding calls the script any more and
        // the default is tsv, but the script is still on disk, so the shape is pinned here
        // rather than left to drift.
        let rows = try state().listWindows(format: .legacy).split(separator: "\n")
        let fields = rows[0].split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        #expect(fields.count == 3)
        #expect(fields[0] == "9607")
        #expect(fields[2] == "29899")
    }

    @Test("legacy omits ignored applications")
    func legacyOmitsIgnored() throws {
        let text = try state().listWindows(format: .legacy)
        #expect(!text.contains("borders"))
        #expect(text.contains("Ghostty"))
    }

    @Test("legacy carries no header, so a parser sees only windows")
    func legacyHasNoHeader() throws {
        let rows = try state().listWindows(format: .legacy).split(separator: "\n")
        #expect(rows.count == 2)
        #expect(!rows[0].contains("windowId"))
    }

    @Test("tsv has a header and adds the title and stack")
    func tsvColumns() throws {
        let rows = try state().listWindows(format: .tsv).split(separator: "\n")
        #expect(rows[0] == "windowId\tpid\tapp\tstack\ttitle")
        let first = rows[1].split(separator: "\t", omittingEmptySubsequences: false)
        #expect(first[0] == "9607")
        #expect(first[2] == "Ghostty")
        #expect(first[3] == "0")
        #expect(first[4] == "spikot-win")
    }

    @Test("tsv field 1 is a window id, not the pid mylauncher used to read")
    func tsvIdentifiesWindows() throws {
        // The whole point of the format change: `focus --window` takes a window number, and
        // field 1 is where that number is. The pid is a separate column, so the two can no
        // longer be confused by a caller counting fields.
        let rows = try state().listWindows(format: .tsv).split(separator: "\n")
        let numbers = Set(
            rows.dropFirst().map { String($0.split(separator: "\t")[0]) })
        let pids = Set(rows.dropFirst().map { String($0.split(separator: "\t")[1]) })
        #expect(numbers == ["9607", "116"])
        #expect(pids == ["29899", "2396"])
        #expect(numbers.isDisjoint(with: pids))
    }

    @Test("json decodes with every field")
    func jsonDecodes() throws {
        let data = Data(try state().listWindows(format: .json).utf8)
        let entries = try JSONDecoder().decode([ListedWindow].self, from: data)

        #expect(entries.count == 2, "the ignored application is excluded")
        let ghostty = entries.first { $0.app == "Ghostty" }
        #expect(ghostty?.windowId == 9607)
        #expect(ghostty?.pid == 29899)
        #expect(ghostty?.stack == 0)
        #expect(ghostty?.title == "spikot-win")
        #expect(ghostty?.bounds.width == 756)
    }

    @Test("A window in no stack reports a nil stack rather than being dropped")
    func windowWithoutStack() throws {
        let orphanState = Fixtures.state(
            windows: [
                Fixtures.window(number: 1, owner: "Orphan", coordX: 400, width: 100)
            ],
            displays: Fixtures.laptopOnly)
        orphanState.initialize()

        let entries = try JSONDecoder().decode(
            [ListedWindow].self,
            from: Data(try orphanState.listWindows(format: .json).utf8))
        #expect(entries.count == 1)
        #expect(entries[0].stack == nil)
    }
}

@Suite("Ignored applications")
struct IgnoredAppsTests {

    @Test("The default ignores borders")
    func defaultIgnores() {
        #expect(Config.standard.ignoredApps == ["borders"])
    }

    @Test("A configured list replaces the default")
    func configurable() {
        let state = Fixtures.state(
            config: Config(useCache: false, ignoredApps: ["Firefox"]),
            windows: [
                Fixtures.window(number: 1, owner: "Firefox", coordX: 0, width: 756),
                Fixtures.window(number: 2, owner: "borders", coordX: 0, width: 756),
            ],
            displays: Fixtures.laptopOnly)
        state.initialize()
        // Firefox is now excluded and borders is not, since the list replaced the default.
        #expect(state.visibleWindows.map { $0.kCGWindowOwnerName } == ["borders"])
    }

    @Test("An empty list manages everything")
    func emptyListManagesAll() {
        let state = Fixtures.state(
            config: Config(useCache: false, ignoredApps: []),
            windows: [Fixtures.window(number: 2, owner: "borders", coordX: 0, width: 756)],
            displays: Fixtures.laptopOnly)
        state.initialize()
        #expect(state.visibleWindows.count == 1)
    }

    @Test("ignoredApps decodes from a config file")
    func decodes() throws {
        let json = #"{"ignoredApps": ["borders", "Dock"]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.ignoredApps == ["borders", "Dock"])
    }
}
