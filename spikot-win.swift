
/* Window Attributes example
{
    kCGWindowAlpha = 1;
    kCGWindowBounds =     {
        Height = 1415;
        Width = 1720;
        X = 1720;
        Y = 25;
    };
    kCGWindowIsOnscreen = 1;
    kCGWindowLayer = 0;
    kCGWindowMemoryUsage = 2288;
    kCGWindowNumber = 3138;
    kCGWindowOwnerName = kitty;
    kCGWindowOwnerPID = 75111;
    kCGWindowSharingState = 0;
    kCGWindowStoreType = 1;
}
 */


import Cocoa

/* Filters
   
   TODO Filter by column
   TODO Take into account displays
   
 Window listing with the OnScreenOnly option returns windows in "depth" order
 withing the same kCGWindowLayer

 When moving between columsn take into account only the first listed window
 of each column
 
*/

let moves:[String:[String:String]] = [
  "left": ["variable":"X", "offset": "-1"],
  "right": ["variable":"X", "offset": "1"],
  "up": ["variable":"Y", "offset": "-1"],
  "down":["variable":"Y", "offset": "1"]
  ]

let gap = 5

let screenRect = (NSWindow().screen!).frame
let screenMaxX = screenRect.size.width
let screenMaxY = screenRect.size.height

let mode:[String:[String:CGFloat]] = [
  "twoColumns": ["c1":(screenMaxX/4),
                 "c2":(3*screenMaxX/4)],
  "threeColumns": ["c1":(screenMaxX/6),
                   "c2":(screenMaxX/2),
                   "c3":(5*screenMaxX/6)]
  ]

let activeMode = mode["twoColumns"]

/*
let x1 = win.kCGWindowBounds.X
let x2 = x1 + win.kCGWindowBounds.Width
if column.center >  x1 and 
   column.center <  x2
   window is in column
*/

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
let infoList = windowsListInfo as! [[String:Any]]
let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }

NSLog("%@", visibleWindows)
NSLog("%@", activeMode!)

func wip (windows: [[String:Any]], mode: [String:CGFloat]) {
//func wip (mode: [String:CGFloat]) {
    NSLog("%@", windows)
    NSLog("%@", mode)
/*    for win in windows {
        print(win)
    }*/
}

func switchToWindow(direction: String) {
    
    let sortVariable:String = moves[direction]!["variable"]!
    let moveOffset = Int(moves[direction]!["offset"]!)


    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
    let infoList = windowsListInfo as! [[String:Any]]
    let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }

    let sortedWindows = visibleWindows.sorted {
        // TODO Check corner cases
        let b0 = $0["kCGWindowBounds"] as! Dictionary<String, AnyObject>
        let b1 = $1["kCGWindowBounds"] as! Dictionary<String, AnyObject>
        return (b0[sortVariable] as! Int32) < (b1[sortVariable] as! Int32)
    }

    let frontAppPid = NSWorkspace.shared.frontmostApplication!.processIdentifier
    let frontPos:Int? = sortedWindows.firstIndex(where: { ($0["kCGWindowOwnerPID"] as! Int32) == frontAppPid })
    let targetPos = frontPos! + moveOffset!
    let targetWinOwnerPID = sortedWindows[targetPos]["kCGWindowOwnerPID"] as! Int32
    let app = NSRunningApplication(processIdentifier: targetWinOwnerPID)
    app?.activate(options: .activateIgnoringOtherApps)

}

wip_filter(windows: visibleWindows, mode: activeMode!)

// Main
let validArgs = ["left", "right", "up", "down"]
if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        switchToWindow(direction: arg)
    } else {
        print("Argument must be one of \(validArgs)")
    }
}

