import Foundation

struct Move: Codable {
    let variable: String
    let offset: Int
}

let moves: [String: Move] = [
  "left": Move(variable: "X", offset: -1),
  "right": Move(variable: "X", offset: 1),
  "up": Move(variable: "Y", offset: -1),
  "down": Move(variable: "Y", offset: 1)
  ]

struct WindowBounds: Codable, Hashable {
    let height: Int
    let width: Int
    let coordX: Int
    let coordY: Int
}
extension WindowBounds {
    init(dict: [String: Any]) {
        self.height = (dict["Height"] as? Int)!
        self.width = (dict["Width"] as? Int)!
        self.coordX = (dict["X"] as? Int)!
        self.coordY = (dict["Y"] as? Int)!
    }
}

struct Window: Codable, Hashable {
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
    init(dict: [String: Any]) {
        self.kCGWindowAlpha = (dict["kCGWindowAlpha"] as? Int)!
        self.kCGWindowBounds = WindowBounds(dict: (dict["kCGWindowBounds"] as? [String: Any])!)
        self.kCGWindowIsOnscreen = (dict["kCGWindowIsOnscreen"] as? Int)!
        self.kCGWindowLayer = (dict["kCGWindowLayer"] as? Int)!
        self.kCGWindowMemoryUsage = (dict["kCGWindowMemoryUsage"] as? Int)!
        self.kCGWindowNumber = (dict["kCGWindowNumber"] as? Int)!
        self.kCGWindowOwnerName = (dict["kCGWindowOwnerName"] as? String)!
        self.kCGWindowOwnerPID = (dict["kCGWindowOwnerPID"] as? Int32)!
        self.kCGWindowSharingState = (dict["kCGWindowSharingState"] as? Int)!
        self.kCGWindowStoreType = (dict["kCGWindowStoreType"] as? Int)!
    }
    
}

struct WindowMeta: Codable, Hashable {
    let kCGWindowLayer: Int
    let kCGWindowNumber: Int
    let kCGWindowOwnerName: String
    let kCGWindowOwnerPID: Int32
}

extension WindowMeta {
    init(from: Window) {
        self.kCGWindowLayer = from.kCGWindowLayer
        self.kCGWindowNumber = from.kCGWindowNumber
        self.kCGWindowOwnerName = from.kCGWindowOwnerName
        self.kCGWindowOwnerPID = from.kCGWindowOwnerPID
    }
}

public struct Config: Codable {
    public let gap: Int
    public let activeMode: String
    public let cachePath: String
    public let useCache: Bool
}
