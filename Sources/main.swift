import Cocoa
import Foundation

/* Filters
   
   TODO Take into account displays
   
 Window listing with the OnScreenOnly option returns windows in "depth" order
 withing the same kCGWindowLayer

 When moving between columsn take into account only the first listed window
 of each column
 
*/

let state = State()

let config = Config(gap: 5,
                    activeMode: state.modes["twoColumns"]!,
                    stateURL: state.cacheURL,
                    cachedState: false)

// Visible Windows
let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
let infoList = windowsListInfo as! [[String:Any]]
let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }


var stacks: [[Window]] = state.getState(config: config)

// Main
let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        let frontAppPid = NSWorkspace.shared.frontmostApplication!.processIdentifier
        let frontWin:Window? = visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontAppPid })
        let currentStack = windowInColumn(window: frontWin!, mode:config.activeMode) ?? -1
        
        if (arg == "up" || arg == "down") {
            rotateStack(stacks: stacks, currentStack: currentStack, direction: arg)
        } else {
            switchStack(stacks: stacks, currentStack: currentStack, toStack: arg)
        }
    } else {
        print("Argument must be one of \(validArgs)")
    }
} else {
    let stackState = state.loadState(config: config)
    dump(stackState)
    dump(stacks)
    state.dumpState(stacks:stacks, config: config)
}

