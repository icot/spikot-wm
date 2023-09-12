import Foundation

func dumpState(stacks: [[Window]], stateURL: URL) {
    let jEncoder = JSONEncoder()
    let jData = try? jEncoder.encode(stacks)
    print("Saving state to \(stateURL.path)")
    if (fm.fileExists(atPath: stateURL.path) == false) {
        fm.createFile(atPath: stateURL.path, contents: jData)
    } else {
        let fh = try? FileHandle.init(forWritingTo: stateURL)
        fh!.write(jData!)
    }
}

func loadState(stateURL: URL) -> [[Window]]? {
    if (fm.fileExists(atPath: stateURL.path) == true) {
        print("Loading state from \(stateURL.path)")
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
