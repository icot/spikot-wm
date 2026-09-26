import Cocoa
import Foundation

// The system facts `State` needs, behind protocols so a test can supply fixed values.
//
// Without these, `State` called NSScreen.screens, CGWindowListCopyWindowInfo,
// NSWorkspace.frontmostApplication and FileManager.homeDirectoryForCurrentUser
// directly, so no part of it could run without a real display, real windows and a real
// home directory. Every initialiser parameter defaults to the live implementation, so
// production call sites read the same as before.

/// One display, reduced to the fields the stack geometry uses.
///
/// Deliberately not `NSScreen`: a plain value can be built in a test, so the two-monitor
/// layout can be exercised with the external monitor unplugged.
public struct DisplayInfo: Equatable, Sendable {
    /// Full bounds, including the menu bar and Dock.
    public var frame: CGRect
    /// Bounds excluding the menu bar and Dock.
    public var visibleFrame: CGRect
    public var isMain: Bool

    public init(frame: CGRect, visibleFrame: CGRect, isMain: Bool) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
    }
}

/// Supplies the on-screen windows.
public protocol WindowSource {
    /// Windows on layer 0, in the order the window server reports them.
    func onScreenWindows() -> [Window]
}

/// Supplies the attached displays, `screens[0]` first.
public protocol DisplaySource {
    func displays() -> [DisplayInfo]
}

/// Supplies which process is frontmost.
public protocol FocusSource {
    var frontmostPID: Int32? { get }
}

/// Reads and writes the state cache.
public protocol StateStore {
    /// Where the cache lives, for log messages.
    var location: String { get }
    /// Returns nil when there is no cache. Throws when one exists but cannot be used.
    func load() throws -> StateSnapshot?
    func save(_ snapshot: StateSnapshot) throws
}

// MARK: - Live implementations

public struct CGWindowSource: WindowSource {
    public init() {}

    public func onScreenWindows() -> [Window] {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let info = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]]
        else {
            logger.error("CGWindowListCopyWindowInfo returned no usable window list")
            return []
        }
        // A window whose keys do not decode is skipped rather than trapping: the list is
        // a live snapshot and an entry can be missing fields as a window appears or goes.
        return info.compactMap { entry -> Window? in
            guard (entry["kCGWindowLayer"] as? Int) == 0 else { return nil }
            guard let window = Window(dict: entry) else {
                logger.debug("Skipping window with unexpected keys: \(entry.keys.sorted())")
                return nil
            }
            return window
        }
    }
}

public struct NSScreenSource: DisplaySource {
    public init() {}

    public func displays() -> [DisplayInfo] {
        NSScreen.screens.map {
            DisplayInfo(frame: $0.frame, visibleFrame: $0.visibleFrame, isMain: $0 == NSScreen.main)
        }
    }
}

public struct WorkspaceFocusSource: FocusSource {
    public init() {}

    public var frontmostPID: Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// JSON in a file under the home directory.
public struct FileStateStore: StateStore {
    let url: URL

    public var location: String { url.path }

    /// `cachePath` is relative to the home directory, matching `Config.cachePath`.
    public init(cachePath: String) {
        self.url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(cachePath)
    }

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> StateSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(StateSnapshot.self, from: try Data(contentsOf: url))
    }

    /// Atomic on purpose: it writes a temporary file and renames it, so a shorter payload
    /// cannot leave the tail of a longer one behind. See spikot-win-yeh.2.
    public func save(_ snapshot: StateSnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic])
    }
}

/// In-memory store for tests. Starts empty; `save` then `load` round-trips.
public final class InMemoryStateStore: StateStore {
    public private(set) var saved: StateSnapshot?
    public private(set) var saveCount = 0

    public var location: String { "<memory>" }

    public init(initial: StateSnapshot? = nil) {
        self.saved = initial
    }

    public func load() throws -> StateSnapshot? { saved }

    public func save(_ snapshot: StateSnapshot) throws {
        saved = snapshot
        saveCount += 1
    }
}
