import Foundation
import Cocoa
import os
import Logging

// Setup State and Modes

/*

 Compute Stack mode reference points
 Supported modes:
 - twoStacks: Two stacks evenly distributed horizontaly on the primary display
 - threeStacks: Three stacks evenly distributed horizontally on the primary display

 If a secondary display is connected and active, it will be available as stack 0.
 Virtual display location assumed to be horizontal without coordinate overlaps on
 the midpoints

 */

// LoggingSystem.bootstrap { label in
//     var handler = StreamLogHandler.standardOutput(label: label)
//     handler.logLevel = .debug
//     return handler
// }

let logger = Logger(label: "org.traf.spikot-wm")

public class State: Codable {

    var cacheURL: URL
    var modes: [String: [Int]] = [:]
    public var activeMode: [Int] = []
    public var visibleWindows: [Window] = []
    public var stacks: [[Window]] = []
    var config: Config


    public init(gap: Int,
         activeMode: String,
         cachePath: String,
         useCache:  Bool){

        self.config = Config(gap: gap,
                             activeMode: activeMode,
                             cachePath: cachePath,
                             useCache: useCache)
        // Cache path
        let fileM = FileManager()
        self.cacheURL = fileM.homeDirectoryForCurrentUser
        self.cacheURL.appendPathComponent(self.config.cachePath)
    }

    public convenience init(config: Config) {

        self.init(gap: config.gap,
                  activeMode: config.activeMode,
                  cachePath: config.cachePath,
                  useCache: config.useCache)

    }

    public func initialize() {
        self.computeModes()
        self.computeStacks()
        logger.debug("Stacks: \(self.sprintfStacks())")
        let cachedState = self.loadCachedState()
        if self.config.useCache == true && cachedState != nil {
            // Use cache to identify changes in windows location
            if self.modes == cachedState!.modes {
                // The cache is only valid if the screen Distribution or
                // the Config has not changed

                let currentWindowsM = Set(self.visibleWindows.map{WindowMeta(from:$0)})
                let cachedWindowsM = Set(cachedState!.visibleWindows.map{WindowMeta(from:$0)})
                let repeatingWindowsM = currentWindowsM.intersection(cachedWindowsM)
                let newWindowsM = currentWindowsM.subtracting(repeatingWindowsM)
                let closedWindowsM = cachedWindowsM.subtracting(repeatingWindowsM)

                // We start from the cached state
                var newStacks: [[Window]] = cachedState!.stacks

                // And remove closed windows
                if closedWindowsM.count > 0 {
                    logger.debug("Windows closed: \(self.sprintfSet(inSet: closedWindowsM))")
                    for windowM in closedWindowsM {
                        let window = cachedState!.visibleWindows.first(where: { $0.kCGWindowNumber == windowM.kCGWindowNumber })!
                        for (id, stack) in cachedState!.stacks.enumerated() {
                            newStacks[id] = stack.filter({$0 == window })
                        }
                    }
                }
                // Insert newly created windows on top of their positional stack
                if newWindowsM.count > 0 {
                    logger.debug("Windows created: \(self.sprintfSet(inSet: newWindowsM))")
                    for windowM in newWindowsM {
                        let window =  self.visibleWindows.first(where: { $0.kCGWindowNumber == windowM.kCGWindowNumber })!
                        let stack = windowInColumn(window: window, mode: self.activeMode) ?? 1
                        newStacks[stack].insert(window, at: 0)
                    }
                }

                // At this point the remaining case to fix in the stored state is to detect
                // windows who have changed stack. In case of disparities between the newStacks and
                // the current State, we take the window stack position from this last one as the
                // fresher data
                logger.debug("Windows reshuffled")
                for (id, stack) in self.stacks.enumerated() {
                    // Iterate over computed stacks
                    for window in stack where !newStacks[id].contains(window) {
                        // If current position doesn't match the cache need to update
                        newStacks[id].insert(window, at: 0)
                        // Delete from other stacks in cache
                        for (sIndex, _) in newStacks.enumerated() where sIndex != id {
                            let pos = newStacks[sIndex].firstIndex(of: window)
                            if pos != nil {
                                newStacks[sIndex].remove(at: pos!)
                            }
                        }
                    }
                }

                // We override the newly computed stacks with teh generated merge of current and cached state
                self.stacks = newStacks
            }
        }
    }

    /* Itended output example

    262  | Emacs         | *scratch*  —  (110 × 68)
    253  | Firefox       | monitlers-mr - IT-dep CERN Mattermost
    5259 | Ghostty       | …/nile/kbackup/test
    4115 | IntelliJ IDEA | monit-xrootdg-enricher – XrootDEnricher.java

    kCGWindowOwnerPID | kCGWindowOwnerName | kCGWindowNumber
     */

    public func listWindows() -> String {
        var buf: [String] = []
        for window in self.visibleWindows {
            // borders windows are not considered individually
            if window.kCGWindowOwnerName != "borders" {
                let info:[String] = [String(window.kCGWindowNumber).padding(toLength: 10, withPad: " ", startingAt: 0),
                                     window.kCGWindowOwnerName.padding(toLength: 32, withPad: " ", startingAt: 0),
                                     String(window.kCGWindowOwnerPID).padding(toLength: 10,withPad: " ",startingAt: 0)]

                buf.append(info.joined(separator: "\t| "))
            }
        }
        return buf.joined(separator: "\n")
    }

    public func sprintfStacks() -> String {
        var buf: [String] = []
        for stack in self.stacks {
            buf.append((stack.map { $0.kCGWindowOwnerName }).joined(separator: ", "))
        }
        return buf.joined(separator: "|")
    }

    public func printfStacks() {
        for (index, stack) in self.stacks.enumerated() {
            var buf: [String] = []
            print("Stack [\(index)]")
            for window in stack {
                if window.kCGWindowOwnerName != "borders" {
                    buf.append(window.kCGWindowOwnerName)
                }
            }
          print(buf.joined(separator: ", "))
        }
    }

    func sprintfSet(inSet: Set<WindowMeta>) -> String {
        var buf: [String] = []
        for item in inSet {
            buf.append(item.kCGWindowOwnerName)
        }
        return buf.joined(separator: ", ")
    }

    // BUG Can fail if more than one window per process is present
    public func currentStack() -> Int {
        let frontPID = NSWorkspace.shared.frontmostApplication!.processIdentifier
        let frontWin: Window? = self.visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontPID })
        return windowInColumn(window: frontWin!, mode: self.activeMode) ?? -1
    }

    public func flushCurrentState() {
        let jEncoder = JSONEncoder()
        let jData = try? jEncoder.encode(self)
        logger.debug("Saving state to \(self.cacheURL.path)")
        let fileM = FileManager()
        if fileM.fileExists(atPath: self.cacheURL.path) == false {
            fileM.createFile(atPath: self.cacheURL.path, contents: jData)
        } else {
            let fileH = try? FileHandle.init(forWritingTo: self.cacheURL)
            fileH!.write(jData!)
        }

        dump(NSApplication.shared.windows)

    }

    public func loadCachedState() -> State? {
        let fileM = FileManager()
        if fileM.fileExists(atPath: self.cacheURL.path) == true {
            logger.debug("Loading state from \(self.cacheURL.path)")
            let fileH = try? FileHandle.init(forReadingFrom: self.cacheURL)
            let data = fileH!.readDataToEndOfFile()
            let jDecoder = JSONDecoder()
            let jData = try? jDecoder.decode(State.self, from: data)
            return jData
        } else {
            logger.debug("Cache file not found")
            return nil
        }
    }

    func computeStacks() {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = (windowsListInfo as? [[String: Any]])!
        let visibleWindows = infoList.filter {
            ($0["kCGWindowLayer"] as? Int)! == 0 }.map {Window(dict: $0)
        }
        self.visibleWindows = visibleWindows.filter {
            ($0.kCGWindowOwnerName  != "borders" )
        }
        self.stacks = stack(windows: self.visibleWindows, mode: self.activeMode)!
    }

    func computeModes() {
        // Mode computation
        let displays = NSScreen.screens
        let maxX1 = displays[0].frame.size.width
        let maxX2 = (displays.count == 2) ? displays[1].frame.size.width: 0

        // Compute mid horizontal coordinate of secondary monitor
        //   negative if on the left of the primary monitor

        var extMid: Int = 0

        if maxX2 != 0 {
            extMid = (displays[1].frame.origin.x < 0) ?
              -Int(maxX2/2):
              Int(maxX1 + maxX2/2)
        }

        self.modes = (maxX2 != 0) ?
          [
            "twoColumns": [extMid, Int(maxX1/4), Int(3*maxX1/4)],
            "threeColumns": [extMid, Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
          ]:
          [
            "twoColumns": [Int(maxX1/4), Int(3*maxX1/4)],
            "threeColumns": [Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
          ]

        self.activeMode = self.modes[self.config.activeMode]!
    }

    public func focusWindow(windowNumber: String) {

        let app = NSRunningApplication(processIdentifier: Int32(windowNumber)!)
        app?.activate(options: .activateIgnoringOtherApps)
    }

    // public func sendWindow(toStack: String) {
    //     let currentStack = self.currentStack()
    //     var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
    //     // boundary safety
    //     targetStack = (targetStack < 0) ? (config.activeMode.count - 1): targetStack
    //     targetStack = (targetStack > (config.activeMode.count - 1)) ? 0: targetStack

    //     let targetWindow = NSWorkspace.shared.frontmostApplication!.processIdentifier
    //     //let targetWindow = self.stacks[targetStack].first!
    //     let app = NSRunningApplication(processIdentifier: targetWindow)

    //     //move(window: app.mainWindow!, stack: toStack)
    // }

    // TODO Implement direct stack selection
    public func switchStack(toStack: String) {
        let currentStack = self.currentStack()
        var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
        // boundary safety
        targetStack = (targetStack < 0) ? (config.activeMode.count - 1): targetStack
        targetStack = (targetStack > (config.activeMode.count - 1)) ? 0: targetStack

        logger.debug("Switch stack to \(targetStack)")

        let targetWindow = self.stacks[targetStack].first!
        let app = NSRunningApplication(processIdentifier: Int32(targetWindow.kCGWindowNumber))
        app?.activate(options: .activateIgnoringOtherApps)
    }

    public func rotateStack(direction: String) {
        if (self.currentStack() > -1) && (self.stacks[self.currentStack()].count > 1) {
            // Only operate on managed stacks with more than one window
            logger.debug("Rotating stack \(self.currentStack()) with direction \(direction)")

            // Update state
            if direction == "up" {
                self.stacks[self.currentStack()].insert(self.stacks[self.currentStack()].removeLast(), at: 0)
            } else {
                // TODO Buggy somehow?. It might me mismatch during state merging causing the wrong stack order
                self.stacks[self.currentStack()].append(self.stacks[self.currentStack()].removeFirst())
            }

            // Update Cache
            self.flushCurrentState()

            // Select target window
            let targetWindow = self.stacks[self.currentStack()].first!

            // Activate focus
            let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
            app?.activate(options: .activateIgnoringOtherApps)

        }
    }

}
