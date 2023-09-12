import Foundation
import Cocoa

// TODO: Add logic for case where cache is enabled but fails to load
func getState(config: Config) -> [[Window]] {
    var state: [[Window]]?
    if (config.cachedState == true) {
        state = loadState(config: config)
    } else {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
        let infoList = windowsListInfo as! [[String:Any]]
        let visibleWindows = infoList.filter{ $0["kCGWindowLayer"] as! Int == 0 }.map{ Window(dict: $0) }
        state = stack(windows: visibleWindows, mode:config.activeMode)!
        dumpState(stacks: state!, config: config)
    }
    return state!
}

func dumpState(stacks: [[Window]], config: Config) {
    let jEncoder = JSONEncoder()
    let jData = try? jEncoder.encode(stacks)
    print("Saving state to \(config.stateURL.path)")
    if (fm.fileExists(atPath: config.stateURL.path) == false) {
        fm.createFile(atPath: config.stateURL.path, contents: jData)
    } else {
        let fh = try? FileHandle.init(forWritingTo: stateURL)
        fh!.write(jData!)
    }
}

func loadState(config: Config) -> [[Window]]? {
    if (fm.fileExists(atPath: config.stateURL.path) == true) {
        print("Loading state from \(config.stateURL.path)")
        let fh = try? FileHandle.init(forReadingFrom: stateURL)
        let data = fh!.readDataToEndOfFile()
        let jDecoder = JSONDecoder()
        let jData = try? jDecoder.decode([[Window]].self, from: data)
        return jData
    } else {
        print("File doesn't exist")
        return nil
    }
}
