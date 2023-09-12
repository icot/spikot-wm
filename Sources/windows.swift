
func stack(windows: [Window], mode: [Int]) -> [[Window]]? {
    var stacks: [[Window]] = []
    for (stackID, _) in mode.enumerated() {
        let windowsInStack = windows.filter({ windowInColumn(window: $0, mode: mode) == stackID })
        stacks.append(windowsInStack)
    }
    return stacks
}

func windowInColumn(window: Window, mode: [Int]) -> Int? {
    let x1 = window.kCGWindowBounds.x
    let x2 = x1 + window.kCGWindowBounds.width
    for (position, stackCenter) in mode.enumerated() {
        if ((stackCenter >  x1) && (stackCenter <= x2)) {
            // This check assumes windows are properly stacked
            return position
        }
    }
    return nil
}
