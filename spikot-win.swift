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
    let height: Int
    let width: Int
    let x: Int
    let y: Int
}
extension WindowBounds{
    init(dict:[String:Any]) {
        self.height = dict["Height"] as! Int
        self.width = dict["Width"] as! Int
        self.x = dict["X"] as! Int
        self.y = dict["Y"] as! Int
    }
}
    
struct Window {
    let kCGWindowAlpha: Int
    let kCGWindowBounds: WindowBounds
    let kCGWindowIsOnscreen: Int
    let kCGWindowLayer: Int
    let kCGWindowMemoryUsage: Int
    let kCGWindowNumber: Int
    let kCGWindowOwnerName: String
    let kCGWindowOwnerPID: Int32
    let kCGWindowSharingState: Int
    let kCGWindowStoreType: Int
}
// Extend definition to initialize from Dictionary [String, Any] as returned by CGWindowListcopywindowinfo
extension Window {
    init(dict:[String:Any]) {
        self.kCGWindowAlpha = dict["kCGWindowAlpha"] as! Int
        self.kCGWindowBounds = WindowBounds(dict: dict["kCGWindowBounds"] as! [String:Any])
        self.kCGWindowIsOnscreen = dict["kCGWindowIsOnscreen"] as! Int
        self.kCGWindowLayer = dict["kCGWindowLayer"] as! Int
        self.kCGWindowMemoryUsage = dict["kCGWindowMemoryUsage"] as! Int
        self.kCGWindowNumber = dict["kCGWindowNumber"] as! Int 
        self.kCGWindowOwnerName = dict["kCGWindowOwnerName"] as! String
        self.kCGWindowOwnerPID = dict["kCGWindowOwnerPID"] as! Int32
        self.kCGWindowSharingState = dict["kCGWindowSharingState"] as! Int
        self.kCGWindowStoreType = dict["kCGWindowStoreType"] as! Int
    }
}

struct Screen {
    let rect: Any
    let maxX: Int
    let maxY: Int
}

struct Config {
    let gap: Int
    let activeMode: [Int]
}

let screenRect = (NSWindow().screen!).frame
let screenMaxX = screenRect.size.width
let screenMaxY = screenRect.size.height

let mode:[String:[Int]] = [
  "twoColumns": [Int(screenMaxX/4), Int(3*screenMaxX/4)],
  "threeColumns": [Int(screenMaxX/6), Int(screenMaxX/2), Int(5*screenMaxX/6)]
  ]

let activeMode = mode["twoColumns"]!

let config = Config(gap: 5, activeMode: mode["twoColumns"]!)

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
let infoList = windowsListInfo as! [[String:Any]]
let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }

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
                                         
func wip_filter (windows: [Window], columns: [Int]) {
    for win in windows {
        let stackNumber = windowInColumn(window:win, mode:activeMode) ?? -1
        print(">>> \(win.kCGWindowOwnerName) in stack: \(stackNumber)")
    }
}

func switchStack(direction: String) {
    // 1. Get stack for frontmostApplication
    // 2. Compute target stack by adding offset based on direction
    // 3. Filter out first window in stack with target stack number
    // 4. Set window active
}

func rotateStack(windows: [Window], direction: String) {
    // 1. Get stack for frontmostApplication
    // 2. Filter out list of windows in stack
    // 3. Set window active based on direction offset
    let frontAppPid = NSWorkspace.shared.frontmostApplication!.processIdentifier
    let frontWin:Window? = windows.first(where: { $0.kCGWindowOwnerPID == frontAppPid })
    let stackID = windowInColumn(window: frontWin!, mode:activeMode) ?? -1
    let windowsInStack = windows.filter( { windowInColumn(window: $0, mode:activeMode) == stackID } )
    NSLog("Windows in stack %d", stackID)
    NSLog("%@",windowsInStack)
    if ((stackID > -1) && (windowsInStack.count > 1)) {
        // Only operate on managed stacks with more than one window
        // TODO Without stack management it may only switch topmost two windows in stack? (three with
        //      negative offset?. Need to how OSX "stacks" the windows on its own
        let offset = moves[direction]!.offset
        var targetWindow: Window
        if (offset < 0) {
            targetWindow = windowsInStack[windowsInStack.count + offset]
        } else {
            targetWindow = windowsInStack[offset]            
        }
        let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
        app?.activate(options: .activateIgnoringOtherApps)
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

wip_filter(windows: visibleWindows, columns: activeMode)

// Main
let validArgs = ["left", "right", "up", "down"]
if CommandLine.arguments.count == 2 {
    let arg = CommandLine.arguments[1]
    if validArgs.contains(arg) {
        if (arg == "up" || arg == "down") {
            rotateStack(windows: visibleWindows, direction: arg)
        } else {
            // switchStack
            switchToWindow(direction: arg)            
        }
    } else {
        print("Argument must be one of \(validArgs)")
    }
}

