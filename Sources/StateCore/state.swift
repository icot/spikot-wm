import Cocoa
import Foundation
import Logging

// Setup State and Modes

/*

 Compute Stack mode reference points
 Supported modes:
 - twoColumns: Two stacks evenly distributed horizontally on the primary display
 - threeColumns: Three stacks evenly distributed horizontally on the primary display

 If a secondary display is connected and active, it will be available as stack 0.
 Virtual display location assumed to be horizontal without coordinate overlaps on
 the midpoints

 */

let logger = Logger(label: "org.traf.spikot-wm")

/// Routes `logger` output to stderr at the requested level.
///
/// Must be called once from an executable's entry point: `LoggingSystem.bootstrap`
/// is a process-wide side effect, and a library's file-scope code never runs, so
/// this cannot live at file scope here.
///
/// stderr rather than stdout on purpose: stdout carries the parsed output of
/// `list`, which external scripts read.
///
/// The level comes from `SPIKOT_LOG` (`trace`, `debug`, `info`, `notice`,
/// `warning`, `error`, `critical`) and falls back to `level`.
public func bootstrapLogging(level: Logger.Level = .info) {
    let resolved = ProcessInfo.processInfo.environment["SPIKOT_LOG"]
        .flatMap { Logger.Level(rawValue: $0.lowercased()) } ?? level
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardError(label: label)
        handler.logLevel = resolved
        return handler
    }
}

public class State: Codable {

    var cacheURL: URL
    var modes: [String: [Int]] = [:]
    public var activeMode: [Int] = []
    public var visibleWindows: [Window] = []
    public var stacks: [[Window]] = []
    public var config: Config

    public init(
        gap: Int,
        activeMode: String,
        cachePath: String,
        useCache: Bool
    ) {

        self.config = Config(
            gap: gap,
            activeMode: activeMode,
            cachePath: cachePath,
            useCache: useCache)
        // Cache path
        let fileM = FileManager()
        self.cacheURL = fileM.homeDirectoryForCurrentUser
        self.cacheURL.appendPathComponent(self.config.cachePath)
    }

    public convenience init(config: Config) {

        self.init(
            gap: config.gap,
            activeMode: config.activeMode,
            cachePath: config.cachePath,
            useCache: config.useCache)

    }

    public func initialize() {
        self.computeModes()
        self.computeStacks()
        logger.debug("Stacks: \(self.sprintfStacks())")
        let cachedState = self.loadCachedState()
        guard self.config.useCache, let cachedState else { return }
        // The cache is only valid if the screen Distribution or
        // the Config has not changed
        guard self.modes == cachedState.modes else { return }
        // We override the newly computed stacks with the generated merge of current
        // and cached state
        self.stacks = self.mergeCachedStacks(with: cachedState)
    }

    /// Uses the cache to identify changes in window location, so that stack membership
    /// survives across runs.
    private func mergeCachedStacks(with cachedState: State) -> [[Window]] {
        let currentWindowsM = Set(self.visibleWindows.map { WindowMeta(from: $0) })
        let cachedWindowsM = Set(cachedState.visibleWindows.map { WindowMeta(from: $0) })
        let repeatingWindowsM = currentWindowsM.intersection(cachedWindowsM)
        let newWindowsM = currentWindowsM.subtracting(repeatingWindowsM)
        let closedWindowsM = cachedWindowsM.subtracting(repeatingWindowsM)

        // We start from the cached state
        var newStacks: [[Window]] = cachedState.stacks
        self.removeClosedWindows(closedWindowsM, from: &newStacks, cachedState: cachedState)
        self.insertNewWindows(newWindowsM, into: &newStacks)
        self.reshuffleMovedWindows(in: &newStacks)
        return newStacks
    }

    private func removeClosedWindows(
        _ closedWindowsM: Set<WindowMeta>,
        from newStacks: inout [[Window]],
        cachedState: State
    ) {
        guard closedWindowsM.count > 0 else { return }
        logger.debug("Windows closed: \(self.sprintfSet(inSet: closedWindowsM))")
        for windowM in closedWindowsM {
            let window = cachedState.visibleWindows.first(where: {
                $0.kCGWindowNumber == windowM.kCGWindowNumber
            })!
            // BUG This keeps only the closed window instead of dropping it; see
            // suggestions.md ("Window Filtering Logic").
            for (id, stack) in cachedState.stacks.enumerated() {
                newStacks[id] = stack.filter({ $0 == window })
            }
        }
    }

    /// Insert newly created windows on top of their positional stack
    private func insertNewWindows(_ newWindowsM: Set<WindowMeta>, into newStacks: inout [[Window]]) {
        guard newWindowsM.count > 0 else { return }
        logger.debug("Windows created: \(self.sprintfSet(inSet: newWindowsM))")
        for windowM in newWindowsM {
            let window = self.visibleWindows.first(where: {
                $0.kCGWindowNumber == windowM.kCGWindowNumber
            })!
            let stack = windowInColumn(window: window, mode: self.activeMode) ?? 1
            newStacks[stack].insert(window, at: 0)
        }
    }

    /// Detect windows who have changed stack. In case of disparities between the
    /// newStacks and the current State, we take the window stack position from this
    /// last one as the fresher data.
    private func reshuffleMovedWindows(in newStacks: inout [[Window]]) {
        logger.debug("Windows reshuffled")
        for (id, stack) in self.stacks.enumerated() {
            // Iterate over computed stacks
            for window in stack where !newStacks[id].contains(window) {
                // If current position doesn't match the cache need to update
                newStacks[id].insert(window, at: 0)
                // Delete from other stacks in cache
                for sIndex in newStacks.indices where sIndex != id {
                    if let pos = newStacks[sIndex].firstIndex(of: window) {
                        newStacks[sIndex].remove(at: pos)
                    }
                }
            }
        }
    }

    /* Itended output example

    262  | Emacs         | *scratch*  —  (110 × 68)
    253  | Firefox       | monitlers-mr - IT-dep CERN Mattermost
    5259 | Ghostty       | …/nile/kbackup/test
    4115 | IntelliJ IDEA | monit-xrootdg-enricher – XrootDEnricher.java

    kCGWindowOwnerPID | kCGWindowOwnerName | kCGWindowNumber
     */

    public func listWindows() -> String {
        var buf: [String] = []
        // borders windows are not considered individually
        for window in self.visibleWindows where window.kCGWindowOwnerName != "borders" {
            let info: [String] = [
                String(window.kCGWindowNumber).padding(
                    toLength: 10, withPad: " ", startingAt: 0),
                window.kCGWindowOwnerName.padding(toLength: 32, withPad: " ", startingAt: 0),
                String(window.kCGWindowOwnerPID).padding(
                    toLength: 10, withPad: " ", startingAt: 0),
            ]

            buf.append(info.joined(separator: "\t| "))
        }
        return buf.joined(separator: "\n")
    }

    public func sprintfStacks() -> String {
        var buf: [String] = []
        for stack in self.stacks {
            buf.append((stack.map { $0.kCGWindowOwnerName }).joined(separator: ", "))
        }
        return buf.joined(separator: "|")
    }

    public func printfStacks() {
        for (index, stack) in self.stacks.enumerated() {
            var buf: [String] = []
            print("Stack [\(index)]")
            for window in stack where window.kCGWindowOwnerName != "borders" {
                buf.append(window.kCGWindowOwnerName)
            }
            print(buf.joined(separator: ", "))
        }
    }

    func sprintfSet(inSet: Set<WindowMeta>) -> String {
        var buf: [String] = []
        for item in inSet {
            buf.append(item.kCGWindowOwnerName)
        }
        return buf.joined(separator: ", ")
    }

    // BUG Can fail if more than one window per process is present
    public func currentStack() -> Int {
        let frontPID = NSWorkspace.shared.frontmostApplication!.processIdentifier
        let frontWin: Window? = self.visibleWindows.first(where: {
            $0.kCGWindowOwnerPID == frontPID
        })
        return windowInColumn(window: frontWin!, mode: self.activeMode) ?? -1
    }

    /// Writes the current state to the cache file, replacing any previous contents.
    ///
    /// The write is atomic: `Data.write(to:options:.atomic)` writes a temporary file
    /// and renames it over the target, so a reader never sees a half-written file and
    /// a shorter payload cannot leave the tail of a longer one behind.
    ///
    /// The previous implementation opened the existing file with
    /// `FileHandle(forWritingTo:)`, which seeks to offset 0 but does not truncate.
    /// Writing a shorter payload therefore left trailing bytes of the earlier, longer
    /// write past the end of the new JSON, and `loadCachedState()` then failed to
    /// decode it for every subsequent run.
    public func flushCurrentState() {
        let jEncoder = JSONEncoder()
        do {
            let jData = try jEncoder.encode(self)
            logger.debug("Saving state to \(self.cacheURL.path) (\(jData.count) bytes)")
            try jData.write(to: self.cacheURL, options: [.atomic])
        } catch {
            logger.error("Failed to save state to \(self.cacheURL.path): \(error)")
        }
    }

    /// Reads the cached state, or nil when there is no usable cache.
    ///
    /// A decode failure is logged rather than swallowed. It means the cache is being
    /// discarded and stack membership will not survive this run, which is worth
    /// seeing instead of silently losing.
    public func loadCachedState() -> State? {
        guard FileManager().fileExists(atPath: self.cacheURL.path) else {
            logger.debug("Cache file not found at \(self.cacheURL.path)")
            return nil
        }
        logger.debug("Loading state from \(self.cacheURL.path)")
        do {
            let data = try Data(contentsOf: self.cacheURL)
            return try JSONDecoder().decode(State.self, from: data)
        } catch {
            logger.error("Discarding unusable cache at \(self.cacheURL.path): \(error)")
            return nil
        }
    }

    func computeStacks() {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = (windowsListInfo as? [[String: Any]])!
        let visibleWindows = infoList.filter {
            ($0["kCGWindowLayer"] as? Int)! == 0
        }.map {
            Window(dict: $0)
        }
        self.visibleWindows = visibleWindows.filter {
            ($0.kCGWindowOwnerName != "borders")
        }
        self.stacks = stack(windows: self.visibleWindows, mode: self.activeMode)!
    }

    func computeModes() {
        // Mode computation
        let displays = NSScreen.screens
        let maxX1 = displays[0].frame.size.width
        let maxX2 = (displays.count == 2) ? displays[1].frame.size.width : 0

        // Compute mid horizontal coordinate of secondary monitor
        //   negative if on the left of the primary monitor

        var extMid: Int = 0

        if maxX2 != 0 {
            extMid = (displays[1].frame.origin.x < 0) ? -Int(maxX2 / 2) : Int(maxX1 + maxX2 / 2)
        }

        self.modes =
            (maxX2 != 0)
            ? [
                "twoColumns": [extMid, Int(maxX1 / 4), Int(3 * maxX1 / 4)],
                "threeColumns": [extMid, Int(maxX1 / 6), Int(maxX1 / 2), Int(5 * maxX1 / 6)],
            ]
            : [
                "twoColumns": [Int(maxX1 / 4), Int(3 * maxX1 / 4)],
                "threeColumns": [Int(maxX1 / 6), Int(maxX1 / 2), Int(5 * maxX1 / 6)],
            ]

        self.activeMode = self.modes[self.config.activeMode]!
    }

    public func focusWindow(windowNumber: String) {
        let app = NSRunningApplication(processIdentifier: Int32(windowNumber)!)
        app?.activate()
    }

    public func switchStack(toStack: String) {

        let currentStack = self.currentStack()
        var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
        logger.info("Switch stack from \(currentStack) to \(targetStack)")

        // boundary safety
        targetStack = (targetStack < 0) ? (config.activeMode.count - 1) : targetStack
        targetStack = (targetStack > (config.activeMode.count - 1)) ? 0 : targetStack
        logger.info("[Safe] Switch stack from \(currentStack) to \(targetStack)")
        // TODO Implement with guards

        let targetWindow = self.stacks[targetStack].first!
        logger.info("Target Stack: \(self.stacks[targetStack])")
        logger.info("Target Window: \(targetWindow)")

        let app = NSRunningApplication(processIdentifier: Int32(targetWindow.kCGWindowOwnerPID))
        app?.activate()
    }

    public func rotateStack(direction: String) {
        if (self.currentStack() > -1) && (self.stacks[self.currentStack()].count > 1) {
            // Only operate on managed stacks with more than one window
            logger.debug("Rotating stack \(self.currentStack()) with direction \(direction)")

            // Update state
            if direction == "up" {
                self.stacks[self.currentStack()].insert(
                    self.stacks[self.currentStack()].removeLast(), at: 0)
            } else {
                // TODO Buggy somehow?. It might me mismatch during state merging causing the wrong stack order
                self.stacks[self.currentStack()].append(
                    self.stacks[self.currentStack()].removeFirst())
            }

            // Update Cache
            self.flushCurrentState()

            // Select target window
            let targetWindow = self.stacks[self.currentStack()].first!

            // Activate focus
            let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
            app?.activate()

        }
    }

}
