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
        self.removeClosedWindows(closedWindowsM, from: &newStacks, cachedState: cachedState)
        self.insertNewWindows(newWindowsM, into: &newStacks)
        self.reshuffleMovedWindows(in: &newStacks)
        return newStacks
    }

    func removeClosedWindows(
        _ closedWindowsM: Set<WindowMeta>,
        from newStacks: inout [[Window]],
        cachedState: StateSnapshot
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
    func insertNewWindows(_ newWindowsM: Set<WindowMeta>, into newStacks: inout [[Window]]) {
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
