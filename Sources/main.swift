import Cocoa
import Foundation

/* Filters
   
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

struct WindowBounds: Codable {
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
    
struct Window: Codable {
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

let config = Config(gap: 5, activeMode: mode["twoColumns"]!)

// Visible Windows
let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
let infoList = windowsListInfo as! [[String:Any]]
let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }

func stack(windows: [Window], mode: [Int]) -> [[Window]]? {
    var stacks: [[Window]] = []
    for (stackID, _) in mode.enumerated() {
        let windowsInStack = windows.filter({ windowInColumn(window: $0, mode:activeMode) == stackID })
        stacks.append(windowsInStack)
    }
    return stacks
}

var stacks: [[Window]] = stack(windows: visibleWindows, mode:activeMode)!

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
                                         
func switchStack(stacks:[[Window]], currentStack: Int, toStack: String) {
    
    var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
    // boundary safety
    targetStack = (targetStack < 0) ? (activeMode.count - 1) : targetStack
    targetStack = (targetStack > (activeMode.count - 1)) ? 0 : targetStack
    
    NSLog("Switch stack to %d", targetStack)
    
    let targetWindow = stacks[targetStack].first!
    let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
    app?.activate(options: .activateIgnoringOtherApps)
}

func rotateStack(stacks: [[Window]], currentStack: Int, direction: String) {
    // 1. Get stack for frontmostApplication
    // 2. Filter out list of windows in stack
    // 3. Set window active based on direction offset
    let windowsInStack = stacks[currentStack]
    if ((currentStack > -1) && (windowsInStack.count > 1)) {
        // Only operate on managed stacks with more than one window
        // TODO Without stack management it may only switch topmost two windows in stack? (three with
        //      negative offset?. Need to how OSX "stacks" the windows on its own
        let offset = moves[direction]!.offset
        NSLog("Rotating stack %d with offset %d", currentStack, offset)
        let targetWindow: Window = (offset < 0) ?
          windowsInStack[windowsInStack.count + offset] :
          windowsInStack[offset]
        let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
        app?.activate(options: .activateIgnoringOtherApps)

        // up -> stack.insert(a.removeLast(), at:0)
        // down -> stack.append(a.removeFirst())
        
    }
}


func dumpState(stacks: [[Window]]) {
    let jEncoder = JSONEncoder()
    let jData = try? jEncoder.encode(stacks)
    let fm = FileManager()
    var stateURL = fm.homeDirectoryForCurrentUser
    stateURL.appendPathComponent(".spikot-wm-state.json")
    if (fm.fileExists(atPath: stateURL.path) == false) {
        fm.createFile(atPath: stateURL.path, contents: jData)
    } else {
        let fh = try? FileHandle.init(forWritingTo: stateURL)
        fh!.write(jData!)
    }
}

func loadState() -> [[Window]]? {
    let fm = FileManager()
    var stateURL = fm.homeDirectoryForCurrentUser
    stateURL.appendPathComponent(".spikot-wm-state.json")
    if (fm.fileExists(atPath: stateURL.path) == true) {
        let fh = try? FileHandle.init(forReadingFrom: stateURL)
        let data = fh!.readDataToEndOfFile()
        let jDecoder = JSONDecoder()
        let jData = try? jDecoder.decode([[Window]].self, from: data)
        return jData
    } else {
        return nil
    }
}

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
    print(">> Loading state")
    dump(loadState()!)
    print(">> Saving state")
    dump(stacks)
    dumpState(stacks:stacks)
}

