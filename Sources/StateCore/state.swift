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

public class State {

    var modes: [String: [Int]] = [:]
    public var activeMode: [Int] = []
    public var visibleWindows: [Window] = []
    public var stacks: [[Window]] = []
    public var config: Config

    let windowSource: WindowSource
    let displaySource: DisplaySource
    let focusSource: FocusSource
    let store: StateStore

    public init(
        config: Config,
        windows: WindowSource = CGWindowSource(),
        displays: DisplaySource = NSScreenSource(),
        focus: FocusSource = WorkspaceFocusSource(),
        store: StateStore? = nil
    ) {
        self.config = config
        self.windowSource = windows
        self.displaySource = displays
        self.focusSource = focus
        self.store = store ?? FileStateStore(cachePath: config.cachePath)
    }

    /// The persisted form of the current state.
    public func snapshot() -> StateSnapshot {
        StateSnapshot(
            modes: modes,
            activeMode: activeMode,
            visibleWindows: visibleWindows,
            stacks: stacks,
            config: config)
    }

    public func initialize() {
        self.computeModes()
        self.computeStacks()
        logger.debug("Stacks: \(self.sprintfStacks())")
        let cachedState = self.loadCachedState()
        guard self.config.useCache, let cachedState else { return }
        // Validity needs both checks. `modes` is the whole table and holds every layout, so
        // it only changes when the display geometry does. `activeMode` is the selected
        // layout's centre points, so it changes when the mode changes *and* when the
        // displays change. Comparing only `modes` accepted a cache recorded under a
        // different layout, whose stacks array has a different length, and the merge then
        // indexed past its end and trapped.
        guard self.modes == cachedState.modes, self.activeMode == cachedState.activeMode else {
            logger.debug("Discarding cache: display layout or mode changed")
            return
        }
        // We override the newly computed stacks with the generated merge of current
        // and cached state
        self.stacks = self.mergeCachedStacks(with: cachedState)
    }

    /* Itended output example

    262  | Emacs         | *scratch*  —  (110 × 68)
    253  | Firefox       | monitlers-mr - IT-dep CERN Mattermost
    5259 | Ghostty       | …/nile/kbackup/test
    4115 | IntelliJ IDEA | monit-xrootdg-enricher – XrootDEnricher.java

    kCGWindowOwnerPID | kCGWindowOwnerName | kCGWindowNumber
     */

    /// Whether a window belongs to an application `Config.ignoredApps` names.
    func isIgnored(_ window: Window) -> Bool {
        config.ignoredApps.contains(window.kCGWindowOwnerName)
    }

    /// The window's title.
    ///
    /// `kCGWindowName` needs Screen Recording for other applications' windows and is nil
    /// without it, which is the case on this machine, so this falls back to `kAXTitle`.
    /// That costs one Accessibility round-trip per window, which is why it is not filled
    /// in during `initialize()`.
    public func title(for window: Window) -> String? {
        if let title = window.title, !title.isEmpty { return title }
        guard
            let found = WindowIdentity.element(
                forWindowID: CGWindowID(window.kCGWindowNumber),
                pid: window.kCGWindowOwnerPID,
                bounds: window.kCGWindowBounds.rect)
        else { return nil }
        return WindowIdentity.title(of: found.element)
    }

    /// Which stack a window is in, or nil when it is in none.
    public func stackIndex(of window: Window) -> Int? {
        stacks.firstIndex { $0.contains(window) }
    }

    // BUG Can fail if more than one window per process is present
    /// The stack holding the frontmost window, or nil when there is nothing to act on.
    ///
    /// nil covers three cases that the old `-1` sentinel conflated, and one that used to
    /// trap: no frontmost application, a frontmost application with no layer-0 window
    /// (Finder with every window closed, or a full-screen app on another Space - this is
    /// what the `frontWin!` force-unwrap crashed on), and a window that covers no stack
    /// centre.
    ///
    /// Still picks the first window belonging to the frontmost process rather than the
    /// focused one, so it can name the wrong window when an application has several.
    /// spikot-win-6sd.4 fixes that with the Accessibility API.
    public func currentStack() -> Int? {
        guard let frontPID = focusSource.frontmostPID else {
            logger.debug("No frontmost application")
            return nil
        }
        guard let frontWin = visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontPID })
        else {
            logger.debug("Frontmost process \(frontPID) has no window in a managed stack")
            return nil
        }
        return windowInColumn(window: frontWin, mode: self.activeMode)
    }

    /// Writes the current state to the cache, replacing any previous contents.
    ///
    /// `FileStateStore.save` is atomic. The original implementation opened the existing
    /// file with `FileHandle(forWritingTo:)`, which seeks to offset 0 but does not
    /// truncate, so a shorter payload left trailing bytes of the earlier, longer write
    /// past the end of the new JSON and the cache never decoded again.
    public func flushCurrentState() {
        do {
            try store.save(snapshot())
            logger.debug("Saved state to \(store.location)")
        } catch {
            logger.error("Failed to save state to \(store.location): \(error)")
        }
    }

    /// Reads the cached snapshot, or nil when there is no usable cache.
    ///
    /// A decode failure is logged rather than swallowed: it means stack membership is
    /// being discarded for this run, which is worth seeing.
    public func loadCachedState() -> StateSnapshot? {
        do {
            guard let snapshot = try store.load() else {
                logger.debug("Cache not found at \(store.location)")
                return nil
            }
            logger.debug("Loaded state from \(store.location)")
            return snapshot
        } catch {
            logger.error("Discarding unusable cache at \(store.location): \(error)")
            return nil
        }
    }

    func computeStacks() {
        self.visibleWindows = windowSource.onScreenWindows().filter { !isIgnored($0) }
        self.stacks = stack(windows: self.visibleWindows, mode: self.activeMode)
    }

    func computeModes() {
        // Mode computation
        let displays = displaySource.displays()
        guard let primary = displays.first else {
            logger.error("No displays reported; keeping the previous mode table")
            return
        }
        let maxX1 = primary.frame.size.width
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

        guard let active = self.modes[self.config.activeMode] else {
            // Config.load validates activeMode against Config.knownModes, so reaching
            // here means the mode table and that list disagree.
            logger.error("Mode '\(self.config.activeMode)' is not in the computed table")
            return
        }
        self.activeMode = active
    }

    /// Raises one window by its `kCGWindowNumber`.
    public func focus(windowNumber: Int) throws {
        guard let window = visibleWindows.first(where: { $0.kCGWindowNumber == windowNumber })
        else {
            throw StackError.unknownWindow(windowNumber)
        }
        raise(window)
    }

    /// Activates an application by pid, leaving macOS to choose which of its windows
    /// comes up.
    ///
    /// Only reachable through the deprecated `focus --window <pid>` path. Use
    /// `focus(windowNumber:)` for a specific window.
    public func activate(pid: Int32) throws {
        guard NSRunningApplication(processIdentifier: pid) != nil else {
            throw StackError.unknownProcess(pid)
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Brings a specific window forward.
    ///
    /// Sets `kAXMain`, performs `kAXRaiseAction`, then activates the owning application.
    /// The three previous call sites only did the last of those, so with several windows
    /// of one application macOS chose which one came up - the bug noted on
    /// `currentStack()`. Falls back to activating the application when the window's
    /// element cannot be resolved.
    func raise(_ window: Window) {
        let raised = WindowIdentity.raiseWindow(
            id: CGWindowID(window.kCGWindowNumber),
            pid: window.kCGWindowOwnerPID,
            bounds: window.kCGWindowBounds.rect)
        if !raised {
            let name = window.kCGWindowOwnerName
            logger.debug(
                "Could not raise window \(window.kCGWindowNumber); activating \(name) instead")
            NSRunningApplication(processIdentifier: window.kCGWindowOwnerPID)?.activate()
        }
    }

    /// Moves focus to another stack.
    ///
    /// `toStack` is either an absolute index or one of `left`/`right`. An absolute index
    /// outside the current layout is an error, while a relative move wraps around.
    ///
    /// The clamp here used to read `config.activeMode.count`, but `Config.activeMode` is
    /// the mode *name*, so that was the character count of "twoColumns" - 10 - rather
    /// than the number of stacks. The clamp therefore never fired and
    /// `stacks[targetStack].first!` trapped on any out-of-range index.
    public func switchStack(toStack: String) throws {
        let stackCount = self.activeMode.count
        guard stackCount > 0 else { throw StackError.noStacks }

        let targetStack: Int
        if let absolute = Int(toStack) {
            guard absolute >= 0 && absolute < stackCount else {
                throw StackError.stackOutOfRange(absolute, count: stackCount)
            }
            targetStack = absolute
        } else {
            guard let move = moves[toStack] else {
                throw StackError.unknownTarget(toStack)
            }
            guard let current = currentStack() else {
                throw StackError.noCurrentStack
            }
            // Wraps in both directions, so repeated moves cycle rather than stopping.
            targetStack = ((current + move.offset) % stackCount + stackCount) % stackCount
            logger.info("Switch stack from \(current) to \(targetStack) of \(stackCount)")
        }

        guard let targetWindow = self.stacks[targetStack].first else {
            throw StackError.emptyStack(targetStack)
        }
        logger.info("Target window: \(targetWindow.kCGWindowOwnerName) (\(targetWindow.kCGWindowNumber))")

        raise(targetWindow)
    }

    /// Rotates the windows within the focused stack and focuses the new head.
    ///
    /// `currentStack()` was called seven times here, each one re-reading the frontmost
    /// application. Since the rotation changes which window is focused, later calls could
    /// return a different stack than the earlier ones, which is the likely cause of the
    /// "buggy somehow" note that used to sit on the `down` branch. It is read once now.
    public func rotateStack(direction: String) throws {
        guard let current = currentStack() else { throw StackError.noCurrentStack }
        guard self.stacks.indices.contains(current) else {
            throw StackError.stackOutOfRange(current, count: self.stacks.count)
        }
        guard ["up", "down"].contains(direction) else {
            throw StackError.unknownTarget(direction)
        }
        guard self.stacks[current].count > 1 else {
            logger.debug("Stack \(current) has \(self.stacks[current].count) window(s); nothing to rotate")
            return
        }

        logger.debug("Rotating stack \(current) \(direction)")
        if direction == "up" {
            self.stacks[current].insert(self.stacks[current].removeLast(), at: 0)
        } else {
            self.stacks[current].append(self.stacks[current].removeFirst())
        }

        self.flushCurrentState()

        guard let targetWindow = self.stacks[current].first else {
            throw StackError.emptyStack(current)
        }
        raise(targetWindow)
    }
}
