
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

struct Move {
    let variable: String
    let offset: Int
}

let moves:[String:Move] = [
  "left": Move(variable:"X", offset: -1),
  "right": Move(variable:"X", offset: 1),
  "up": Move(variable:"Y", offset: -1),
  "down":Move(variable:"Y", offset: 1)
  ]

struct WindowBounds {
    let Height: Int
    let Width: Int
    let X: Int
    let Y: Int
}
    
struct Window {
    let kCGWindowAlpha: Int
    let kCGWindowBounds: WindowBounds
    let kCGWindowIsOnscreen: Int
    let kCGWindowLayer: Int
    let kCGWindowMemoryUsage: Int
    let kCGWindowOwnerName: String
    let kCGWindowOwnerPID: Int
    let kCGWindowSharingState: Int
    let kCGWindowStoreType: Int
}
// Extend definition to initialize from Dictionary [String, Any] as returned by CGWindowListcopywindowinfo
extension Window {
    init(dict:[String:Any]) {
        print(dict)
        self.kCGWindowAlpha = dict["kCGWindowAlpha"] as! Int
        self.kCGWindowBounds = WindowBounds(
          Height: (dict["kCGWindowBounds"] as! [String:Any])["Height"] as! Int,
          Width: (dict["kCGWindowBounds"] as! [String:Any])["Width"] as! Int,
          X: (dict["kCGWindowBounds"] as! [String:Any])["X"] as! Int,
          Y: (dict["kCGWindowBounds"] as! [String:Any])["Y"] as! Int)
        self.kCGWindowIsOnscreen = dict["kCGWindowIsOnscreen"] as! Int
        self.kCGWindowLayer = dict["kCGWindowLayer"] as! Int
        self.kCGWindowMemoryUsage = dict["kCGWindowMemoryUsage"] as! Int
        self.kCGWindowOwnerName = dict["kCGWindowOwnerName"] as! String
        self.kCGWindowOwnerPID = dict["kCGWindowOwnerPID"] as! Int
        self.kCGWindowSharingState = dict["kCGWindowSharingState"] as! Int
        self.kCGWindowStoreType = dict["kCGWindowStoreType"] as! Int        
    }
}

struct Screen {
    let rect: Any
    let MaxX: Int
    let MaxY: Int
}

struct Config {
    let gap: Int
    let activeMode: [String:CGFloat]
}

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

let config = Config(gap: 5, activeMode: mode["twoColumns"]!)

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
let infoList = windowsListInfo as! [[String:Any]]
let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }

NSLog("%@", visibleWindows)
NSLog("%@", activeMode!)


func windowInColumn(window: [String:Any], columnCenter: CGFloat) -> Bool {
    let x1 = (window["kCGWindowBounds"] as! [String:Any])["X"] as! CGFloat
    let x2 = x1 + ((window["kCGWindowBounds"] as! [String:Any])["Width"] as! CGFloat)
    if ((columnCenter >  x1) && (columnCenter <= x2)) {
        return true
    } else {
        return false
    }
}
                                         
func wip_filter (windows: [[String:Any]], mode: [String:CGFloat]) {
    NSLog("%@", windows)
    NSLog("%@", mode)
    for winDict in windows {
        print(type(of:winDict))
        let win = Window(dict: winDict)
        print(type(of:win))
        print(win)
    }
}

func switchToWindow(direction: String) {
    
    let sortVariable = moves[direction]!.variable
    let moveOffset = moves[direction]!.offset

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
    let targetPos = frontPos! + moveOffset
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

