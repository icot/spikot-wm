import Foundation
import Cocoa

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

class State: Codable {

    var cacheURL: URL
    var modes: [String: [Int]] = [:]
    var activeMode: [Int] = []
    var visibleWindows: [Window] = []
    var stacks: [[Window]] = []
    var config: Config

    init(config: Config) {

        self.config = config

        // Cache path
        let fileM = FileManager()
        self.cacheURL = fileM.homeDirectoryForCurrentUser
        self.cacheURL.appendPathComponent(self.config.cachePath)

    }

    func initialize() {
        self.computeModes()
        self.computeStacks()
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
                    NSLog("Windows closed: \(self.sprintfSet(inSet: closedWindowsM))")
                    for windowM in closedWindowsM {
                        let window = cachedState!.visibleWindows.first(where: { $0.kCGWindowNumber == windowM.kCGWindowNumber })!
                        for (id, stack) in cachedState!.stacks.enumerated() {
                            newStacks[id] = stack.filter({$0 == window })
                        }
                    }
                }
                // Insert newly created windows on top of their positional stack
                if newWindowsM.count > 0 {
                    NSLog("Windows created: \(self.sprintfSet(inSet: newWindowsM))")
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
                NSLog("Windows reshuffled")
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

    func sprintfStacks() -> String {
        var buf: [String] = []
        for stack in self.stacks {
            buf.append((stack.map { $0.kCGWindowOwnerName }).joined(separator: ", "))
        }
        return buf.joined(separator: "|")
    }

    func sprintfSet(inSet: Set<WindowMeta>) -> String {
        var buf: [String] = []
        for item in inSet {
            buf.append(item.kCGWindowOwnerName)
        }
        return buf.joined(separator: ", ")
    }

    // BUG Can fail if more than one window per process is present
    func currentStack() -> Int {
        let frontPID = NSWorkspace.shared.frontmostApplication!.processIdentifier
        let frontWin: Window? = self.visibleWindows.first(where: { $0.kCGWindowOwnerPID == frontPID })
        return windowInColumn(window: frontWin!, mode: state.activeMode) ?? -1
    }

    func flushCurrentState() {
        let jEncoder = JSONEncoder()
        let jData = try? jEncoder.encode(self)
        NSLog("Saving state to \(self.cacheURL.path)")
        let fileM = FileManager()
        if fileM.fileExists(atPath: self.cacheURL.path) == false {
            fileM.createFile(atPath: self.cacheURL.path, contents: jData)
        } else {
            let fileH = try? FileHandle.init(forWritingTo: self.cacheURL)
            fileH!.write(jData!)
        }
    }

    func loadCachedState() -> State? {
        let fileM = FileManager()
        if fileM.fileExists(atPath: self.cacheURL.path) == true {
            NSLog("Loading state from \(self.cacheURL.path)")
            let fileH = try? FileHandle.init(forReadingFrom: self.cacheURL)
            let data = fileH!.readDataToEndOfFile()
            let jDecoder = JSONDecoder()
            let jData = try? jDecoder.decode(State.self, from: data)
            return jData
        } else {
            NSLog("Cache file not found")
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
        self.visibleWindows = visibleWindows
        self.stacks = stack(windows: visibleWindows, mode: self.activeMode)!
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

    // TODO Implement direct stack selection
    func switchStack(toStack: String) {
        let currentStack = self.currentStack()
        var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
        // boundary safety
        targetStack = (targetStack < 0) ? (config.activeMode.count - 1): targetStack
        targetStack = (targetStack > (config.activeMode.count - 1)) ? 0: targetStack

        NSLog("Switch stack to %d", targetStack)

        let targetWindow = self.stacks[targetStack].first!
        let app = NSRunningApplication(processIdentifier: Int32(targetWindow.kCGWindowNumber))
        app?.activate(options: .activateIgnoringOtherApps)
    }

    func rotateStack(direction: String) {
        if (self.currentStack() > -1) && (self.stacks[self.currentStack()].count > 1) {
            // Only operate on managed stacks with more than one window
            NSLog("Rotating stack %d with direction %d", self.currentStack(), direction)

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
