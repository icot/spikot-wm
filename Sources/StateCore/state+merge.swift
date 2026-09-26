import Foundation

// Reconciling the freshly computed stacks with the cached ones. Split out of
// state.swift to keep that file under the line limit.

extension State {

    /// Uses the cache to identify changes in window location, so that stack membership
    /// survives across runs.
    func mergeCachedStacks(with cachedState: StateSnapshot) -> [[Window]] {
        let currentWindowsM = Set(self.visibleWindows.map { WindowMeta(from: $0) })
        let cachedWindowsM = Set(cachedState.visibleWindows.map { WindowMeta(from: $0) })
        let repeatingWindowsM = currentWindowsM.intersection(cachedWindowsM)
        let newWindowsM = currentWindowsM.subtracting(repeatingWindowsM)
        let closedWindowsM = cachedWindowsM.subtracting(repeatingWindowsM)

        // We start from the cached state
        var newStacks: [[Window]] = cachedState.stacks
        self.removeClosedWindows(closedWindowsM, from: &newStacks)
        self.insertNewWindows(newWindowsM, into: &newStacks)
        self.reshuffleMovedWindows(in: &newStacks)
        return newStacks
    }

    /// Drops windows that existed in the cache but are no longer on screen.
    ///
    /// One pass over the stacks, filtering by window number. The previous version had
    /// three defects at once: `stack.filter({ $0 == window })` kept *only* the closed
    /// window instead of dropping it; it assigned into `newStacks[id]` from
    /// `cachedState.stacks` on every iteration of the outer loop, so with two closed
    /// windows the second iteration discarded the first one's work; and it force-unwrapped
    /// the lookup of the closed window in the cached list.
    func removeClosedWindows(
        _ closedWindowsM: Set<WindowMeta>,
        from newStacks: inout [[Window]]
    ) {
        guard !closedWindowsM.isEmpty else { return }
        logger.debug("Windows closed: \(self.sprintfSet(inSet: closedWindowsM))")
        let closedNumbers = Set(closedWindowsM.map { $0.kCGWindowNumber })
        newStacks = newStacks.map { stack in
            stack.filter { !closedNumbers.contains($0.kCGWindowNumber) }
        }
    }

    /// Inserts newly created windows on top of their positional stack.
    ///
    /// A window covering no stack centre goes to stack 1, which is the long-standing
    /// behaviour rather than a considered choice. The force-unwrap on the lookup is gone;
    /// a window in the set but not in `visibleWindows` is skipped and logged.
    func insertNewWindows(_ newWindowsM: Set<WindowMeta>, into newStacks: inout [[Window]]) {
        guard !newWindowsM.isEmpty else { return }
        logger.debug("Windows created: \(self.sprintfSet(inSet: newWindowsM))")
        for windowM in newWindowsM {
            guard
                let window = self.visibleWindows.first(where: {
                    $0.kCGWindowNumber == windowM.kCGWindowNumber
                })
            else {
                logger.debug("New window \(windowM.kCGWindowNumber) vanished before merge")
                continue
            }
            let stack = windowInColumn(window: window, mode: self.activeMode) ?? 1
            guard newStacks.indices.contains(stack) else {
                logger.debug("Stack \(stack) is outside the cached layout; skipping")
                continue
            }
            newStacks[stack].insert(window, at: 0)
        }
    }

    /// Detect windows who have changed stack. In case of disparities between the
    /// newStacks and the current State, we take the window stack position from this
    /// last one as the fresher data.
    func reshuffleMovedWindows(in newStacks: inout [[Window]]) {
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
}
