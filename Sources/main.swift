import Cocoa
import Foundation

/* Filters
   
   TODO Take into account displays
   
 Window listing with the OnScreenOnly option returns windows in "depth" order
 withing the same kCGWindowLayer

 When moving between columsn take into account only the first listed window
 of each column
 
*/

/*
 
 Compute Stack mode reference points
 Supported modes:
 - twoStacks: Two stacks evenly distributed horizontaly on the primary display
 - threeStacks: Three stacks evenly distributed horizontally on the primary display

 If a secondary display is connected and active, it will be available as stack 0.
 Virtual display location assumed to be horizontal without coordinate overlaps on
 the midpoints
 
*/

let displays = NSScreen.screens
let maxX1 = displays[0].frame.size.width
let maxX2 = (displays.count == 2) ? displays[1].frame.size.width : 0

// Compute mid horizontal coordinate of secondary monitor
//   negative if on the left of the primary monitor

var extMid: Int = 0

if (maxX2 != 0) {
    extMid = (displays[1].frame.origin.x < 0) ?
      -Int(maxX2/2) :
      Int(maxX1 + maxX2/2)
}
  
let mode:[String:[Int]] = (maxX2 != 0) ?
  [
    "twoColumns"  : [extMid, Int(maxX1/4), Int(3*maxX1/4)],
    "threeColumns": [extMid, Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
  ] :
  [
  "twoColumns"  : [Int(maxX1/4), Int(3*maxX1/4)],
  "threeColumns": [Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
  ] 
  
let activeMode = mode["twoColumns"]!

let fm = FileManager()
var stateURL = fm.homeDirectoryForCurrentUser
stateURL.appendPathComponent(".spikot-wm-state.json")

let config = Config(gap: 5, activeMode: mode["twoColumns"]!, stateURL: stateURL)

// Visible Windows
let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
let infoList = windowsListInfo as! [[String:Any]]
let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }


var stacks: [[Window]] = stack(windows: visibleWindows, mode:activeMode)!

// Main
let validArgs = ["left", "right", "up", "down", "0", "1", "2", "3", "4"]

if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        let frontAppPid = NSWorkspace.shared.frontmostApplication!.processIdentifier
        let frontWin:Window? = visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontAppPid })
        let currentStack = windowInColumn(window: frontWin!, mode:activeMode) ?? -1
        
        if (arg == "up" || arg == "down") {
            rotateStack(stacks: stacks, currentStack: currentStack, direction: arg)
        } else {
            switchStack(stacks: stacks, currentStack: currentStack, toStack: arg)
        }
    } else {
        print("Argument must be one of \(validArgs)")
    }
} else {
    let stackState = loadState(stateURL: config.stateURL)
    dump(stackState)
    dump(stacks)
    dumpState(stacks:stacks, stateURL: config.stateURL)
    print(checkAccess())
}

