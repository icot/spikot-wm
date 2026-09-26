/*

 Window related helper methods

 */

import Cocoa

func stack(windows: [Window], mode: [Int]) -> [[Window]] {
    var stacks: [[Window]] = []
    for stackID in mode.indices {
        let windowsInStack = windows.filter({ windowInColumn(window: $0, mode: mode) == stackID })
        stacks.append(windowsInStack)
    }
    return stacks
}

func windowInColumn(window: Window, mode: [Int]) -> Int? {
    let coordX1 = window.kCGWindowBounds.coordX
    let coordX2 = coordX1 + window.kCGWindowBounds.width
    for (position, stackCenter) in mode.enumerated() {
        if (stackCenter >  coordX1) && (stackCenter <= coordX2) {
            // This check assumes windows are properly stacked
            return position
        }
    }
    return nil
}
