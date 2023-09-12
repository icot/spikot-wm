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


class State {

    var cacheURL: URL
    var modes:[String:[Int]]
    var activeMode: [Int]
    var fm: FileManager
    var visibleWindows: [Window]
    var stacks: [[Window]] = []
    var config: Config
        
    init(config: Config) {

        self.config = config
        
        // Cache path
        self.fm = FileManager()
        self.cacheURL = fm.homeDirectoryForCurrentUser
        self.cacheURL.appendPathComponent(self.config.cachePath)

        // Mode computation
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
        
        self.modes = (maxX2 != 0) ?
          [
            "twoColumns"  : [extMid, Int(maxX1/4), Int(3*maxX1/4)],
            "threeColumns": [extMid, Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
          ] :
          [
            "twoColumns"  : [Int(maxX1/4), Int(3*maxX1/4)],
            "threeColumns": [Int(maxX1/6), Int(maxX1/2), Int(5*maxX1/6)]
          ]

        self.activeMode = self.modes[self.config.activeMode]!

        // Visible Windows
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = windowsListInfo as! [[String:Any]]
        self.visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }

    }

    func initialize() {
        self.stacks = self.getState()
    }

    func dumpState() {
        let jEncoder = JSONEncoder()
        let jData = try? jEncoder.encode(self.stacks)
        print("Saving state to \(self.cacheURL.path)")
        if (self.fm.fileExists(atPath: self.cacheURL.path) == false) {
            self.fm.createFile(atPath: self.cacheURL.path, contents: jData)
        } else {
            let fh = try? FileHandle.init(forWritingTo: self.cacheURL)
            fh!.write(jData!)
        }
    }

    func loadState() -> [[Window]]? {
        if (self.fm.fileExists(atPath: self.cacheURL.path) == true) {
            print("Loading state from \(self.cacheURL.path)")
            let fh = try? FileHandle.init(forReadingFrom: self.cacheURL)
            let data = fh!.readDataToEndOfFile()
            let jDecoder = JSONDecoder()
            let jData = try? jDecoder.decode([[Window]].self, from: data)
            return jData
        } else {
            print("File doesn't exist")
            return nil
        }
    }

    func _getState() -> [[Window]] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = windowsListInfo as! [[String:Any]]
        let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }
        return stack(windows: visibleWindows, mode:self.activeMode)!
    }
    
    func getState() -> [[Window]] {
        var state: [[Window]]?
        if (self.config.useCache == true) {
            state = self.loadState()
            state = (state != nil) ? state : _getState()
        } else {
            state = self._getState()
        }
        return state!
    }

    
}




