import Foundation

@testable import StateCore

// Test doubles and sample data. Nothing here touches the window server, so `swift test`
// runs with the external monitor unplugged and over SSH.

struct FakeWindowSource: WindowSource {
    var windows: [Window]
    func onScreenWindows() -> [Window] { windows }
}

struct FakeDisplaySource: DisplaySource {
    var list: [DisplayInfo]
    func displays() -> [DisplayInfo] { list }
}

struct FakeFocusSource: FocusSource {
    var frontmostPID: Int32?
}

enum Fixtures {
    /// The built-in Retina display alone.
    static let laptopOnly = [
        DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            isMain: true)
    ]

    /// The built-in display plus the 5120x1440 ultrawide to its right, at the negative
    /// y origin the real setup reports.
    static let laptopPlusUltrawide = [
        DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            isMain: true),
        DisplayInfo(
            frame: CGRect(x: 1512, y: -458, width: 5120, height: 1440),
            visibleFrame: CGRect(x: 1512, y: -458, width: 5120, height: 1402),
            isMain: false),
    ]

    static func window(
        number: Int,
        owner: String,
        pid: Int32 = 100,
        coordX: Int,
        width: Int,
        coordY: Int = 0,
        height: Int = 800,
        title: String? = nil
    ) -> Window {
        Window(
            kCGWindowAlpha: 1,
            kCGWindowBounds: WindowBounds(
                height: height, width: width, coordX: coordX, coordY: coordY),
            kCGWindowIsOnscreen: 1,
            kCGWindowLayer: 0,
            kCGWindowMemoryUsage: 0,
            kCGWindowNumber: number,
            kCGWindowOwnerName: owner,
            kCGWindowOwnerPID: pid,
            kCGWindowSharingState: 0,
            kCGWindowStoreType: 1,
            title: title)
    }

    /// A state wired entirely to fakes.
    static func state(
        config: Config = Config(useCache: false),
        windows: [Window] = [],
        displays: [DisplayInfo] = Fixtures.laptopOnly,
        frontmostPID: Int32? = nil,
        store: StateStore = InMemoryStateStore()
    ) -> State {
        State(
            config: config,
            windows: FakeWindowSource(windows: windows),
            displays: FakeDisplaySource(list: displays),
            focus: FakeFocusSource(frontmostPID: frontmostPID),
            store: store)
    }
}
