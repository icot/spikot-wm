
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

func switchToWindow(direction: String) {
    
    let moves:[String:[String:String]] = [
      "left": ["variable":"X", "offset": "-1"],
      "right": ["variable":"X", "offset": "1"],
      "up": ["variable":"Y", "offset": "-1"],
      "down":["variable":"Y", "offset": "1"]]

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

