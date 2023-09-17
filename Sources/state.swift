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
        self.stacks = self.computeStacks()
        let cachedState = self.loadCachedState()
        if self.config.useCache == true && cachedState != nil {
            if self.modes == cachedState!.modes {
                // Screen Distribution or Config has not changed
                let currentWindows = Set(self.visibleWindows)
                let cachedWindows = Set(cachedState!.visibleWindows)
                if cachedWindows == currentWindows {
                    self.stacks = cachedState!.stacks
                } else {
                    // Windows have been created or deleted. Need to update stacking
                    if self.visibleWindows.count > cachedWindows.count {
                        // Window addition. We assume new windows added on top of stack
                        let newWindows = currentWindows.subtracting(cachedWindows)
                        var newStacks: [[Window]] = cachedState!.stacks
                        for window in newWindows {
                            let stack = windowInColumn(window: window, mode: self.activeMode) ?? 1
                            newStacks[stack].insert(window, at: 0)
                        }
                        self.stacks = newStacks
                    } else {
                        let removedWindows = cachedWindows.subtracting(currentWindows)
                        var newStacks: [[Window]] = []
                        for window in removedWindows {
                            for (id, stack) in cachedState!.stacks.enumerated() {
                                newStacks[id] = stack.filter({$0 == window })
                            }
                        }
                        self.stacks = newStacks
                    }
                }
            }

        }
    }

    func flushCurrentState() {
        let jEncoder = JSONEncoder()
        let jData = try? jEncoder.encode(self)
        print("Saving state to \(self.cacheURL.path)")
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
            print("Loading state from \(self.cacheURL.path)")
            let fileH = try? FileHandle.init(forReadingFrom: self.cacheURL)
            let data = fileH!.readDataToEndOfFile()
            let jDecoder = JSONDecoder()
            let jData = try? jDecoder.decode(State.self, from: data)
            return jData
        } else {
            print("File doesn't exist")
            return nil
        }
    }

    func computeStacks() -> [[Window]] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = (windowsListInfo as? [[String: Any]])!
        let visibleWindows = infoList.filter {
            ($0["kCGWindowLayer"] as? Int)! == 0 }.map {Window(dict: $0)
        }
        return stack(windows: visibleWindows, mode: self.activeMode)!
    }

    func computeModes() {
        // Mode computation
        let displays = NSScreen.screens
        let maxX1 = displays[0].frame.size.width
        let maxX2 = (displays.count == 2) ? displays[1].frame.size.width : 0

        // Compute mid horizontal coordinate of secondary monitor
        //   negative if on the left of the primary monitor

        var extMid: Int = 0

        if maxX2 != 0 {
            extMid = (displays[1].frame.origin.x < 0) ?
              -Int(maxX2/2) :
              Int(maxX1 + maxX2/2)
        }

        self.modes = (maxX2 != 0) ?
          [
            "twoColumns": [extMid, Int(maxX1/4), Int(3*maxX1/4)],
            "threeColumns": [extMid, Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
          ] :
          [
            "twoColumns": [Int(maxX1/4), Int(3*maxX1/4)],
            "threeColumns": [Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
          ]

        self.activeMode = self.modes[self.config.activeMode]!
    }

    func switchStack(currentStack: Int, toStack: String) {
        var targetStack: Int = Int(toStack) ?? currentStack + moves[toStack]!.offset
        // boundary safety
        targetStack = (targetStack < 0) ? (config.activeMode.count - 1) : targetStack
        targetStack = (targetStack > (config.activeMode.count - 1)) ? 0 : targetStack

        NSLog("Switch stack to %d", targetStack)

        let targetWindow = self.stacks[targetStack].first!
        let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
        app?.activate(options: .activateIgnoringOtherApps)
    }

    func rotateStack(currentStack: Int, direction: String) {
    
        let windowsInStack = self.stacks[currentStack]
        if (currentStack > -1) && (windowsInStack.count > 1) {
            // Only operate on managed stacks with more than one window
            let offset = moves[direction]!.offset
            NSLog("Rotating stack %d with offset %d", currentStack, offset)

            // Select target window
            let targetWindow: Window = (offset < 0) ?
              windowsInStack[windowsInStack.count + offset] :
              windowsInStack[offset]

            // Update cached state
            if direction == "up" {
                self.stacks[currentStack].insert(self.stacks[currentStack].removeLast(), at:0)
            } else {
                self.stacks[currentStack].append(self.stacks[currentStack].removeFirst())
            }
            self.flushCurrentState()

            // Activate focus
            let app = NSRunningApplication(processIdentifier: targetWindow.kCGWindowOwnerPID)
            app?.activate(options: .activateIgnoringOtherApps)

        }
    }


}
