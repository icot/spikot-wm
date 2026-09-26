import Foundation

struct Move: Codable {
    let offset: Int
}

let moves: [String: Move] = [
  "left": Move(offset: -1),
  "right": Move(offset: 1),
  "up": Move(offset: -1),
  "down": Move(offset: 1),
]

public struct WindowBounds: Codable, Hashable {
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

public struct Window: Codable, Hashable {
    public let kCGWindowAlpha: Int
    public let kCGWindowBounds: WindowBounds
    public let kCGWindowIsOnscreen: Int
    public let kCGWindowLayer: Int
    public let kCGWindowMemoryUsage: Int
    public let kCGWindowNumber: Int
    public let kCGWindowOwnerName: String
    public let kCGWindowOwnerPID: Int32
    public let kCGWindowSharingState: Int
    public let kCGWindowStoreType: Int
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
