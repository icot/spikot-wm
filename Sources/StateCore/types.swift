import CoreGraphics
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
    public let height: Int
    public let width: Int
    public let coordX: Int
    public let coordY: Int

    /// The same rectangle in CGWindowList coordinates: top-left origin, y increasing
    /// downwards, matching what the Accessibility API reports and the opposite of
    /// `NSScreen.frame`.
    public var rect: CGRect {
        CGRect(x: coordX, y: coordY, width: width, height: height)
    }
}
extension WindowBounds {
    /// Returns nil when a key is absent or the wrong type, rather than trapping: the
    /// CGWindowList snapshot is live and entries can be incomplete.
    init?(dict: [String: Any]) {
        guard let height = dict["Height"] as? Int,
            let width = dict["Width"] as? Int,
            let coordX = dict["X"] as? Int,
            let coordY = dict["Y"] as? Int
        else { return nil }
        self.height = height
        self.width = width
        self.coordX = coordX
        self.coordY = coordY
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
    /// Returns nil when any key is absent or the wrong type. See `WindowBounds.init?`.
    ///
    /// kCGWindowIsOnscreen is absent for some windows, so it defaults to 0 instead of
    /// rejecting the whole entry.
    init?(dict: [String: Any]) {
        guard let alpha = dict["kCGWindowAlpha"] as? Int,
            let boundsDict = dict["kCGWindowBounds"] as? [String: Any],
            let bounds = WindowBounds(dict: boundsDict),
            let layer = dict["kCGWindowLayer"] as? Int,
            let memoryUsage = dict["kCGWindowMemoryUsage"] as? Int,
            let number = dict["kCGWindowNumber"] as? Int,
            let ownerName = dict["kCGWindowOwnerName"] as? String,
            let ownerPID = dict["kCGWindowOwnerPID"] as? Int32,
            let sharingState = dict["kCGWindowSharingState"] as? Int,
            let storeType = dict["kCGWindowStoreType"] as? Int
        else { return nil }
        self.kCGWindowAlpha = alpha
        self.kCGWindowBounds = bounds
        self.kCGWindowIsOnscreen = (dict["kCGWindowIsOnscreen"] as? Int) ?? 0
        self.kCGWindowLayer = layer
        self.kCGWindowMemoryUsage = memoryUsage
        self.kCGWindowNumber = number
        self.kCGWindowOwnerName = ownerName
        self.kCGWindowOwnerPID = ownerPID
        self.kCGWindowSharingState = sharingState
        self.kCGWindowStoreType = storeType
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

/// Everything written to the cache file.
///
/// Split out of `State` so `State` can hold non-`Codable` protocol dependencies: adding
/// them to a `Codable` class breaks the synthesised conformance. It also stops the cache
/// carrying the absolute `cacheURL`, which the old `State: Codable` serialised.
public struct StateSnapshot: Codable, Equatable {
    public var modes: [String: [Int]]
    public var activeMode: [Int]
    public var visibleWindows: [Window]
    public var stacks: [[Window]]
    public var config: Config

    public init(
        modes: [String: [Int]],
        activeMode: [Int],
        visibleWindows: [Window],
        stacks: [[Window]],
        config: Config
    ) {
        self.modes = modes
        self.activeMode = activeMode
        self.visibleWindows = visibleWindows
        self.stacks = stacks
        self.config = config
    }
}
