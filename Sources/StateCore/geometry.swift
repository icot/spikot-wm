import Foundation

/// Display geometry: coordinate spaces, gaps, and which rectangle each stack gets.
///
/// Separate from `State` and free of AppKit so it can be tested against fixed display
/// fixtures, with the external monitor unplugged.
public enum Geometry {

    /// The y coordinate to flip about: the top of `displays[0]`.
    ///
    /// AppKit measures from the bottom-left of the primary display upwards; the
    /// Accessibility API and `CGWindowList` measure from its top-left downwards. Converting
    /// needs the primary display's `maxY` and nothing else, which is why this takes the whole
    /// list and reads only the first entry — the same rule as Rectangle's
    /// `CGRect.screenFlipped` (`Rectangle/Utilities/CGExtension.swift:12-17`), which reads
    /// `NSScreen.screens[0].frame.maxY`.
    public static func flipAxis(_ displays: [DisplayInfo]) -> CGFloat {
        displays.first?.frame.maxY ?? 0
    }

    /// Converts a rect between the two vertical conventions.
    ///
    /// The operation is its own inverse, so there is one function rather than a pair: applying
    /// it twice returns the original rect. Width and height are untouched; only the origin
    /// moves, from the bottom-left corner to the top-left one.
    public static func flipped(_ rect: CGRect, axis: CGFloat) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(
            x: rect.origin.x, y: axis - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Displays in left-to-right order, which is the order a stack list should follow.
    ///
    /// Not the order `NSScreen.screens` reports: that puts the primary display first whatever
    /// its position, so on this machine the built-in display comes before an external monitor
    /// sitting to its left.
    public static func leftToRight(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        displays.sorted { $0.frame.minX < $1.frame.minX }
    }
}

extension State {
    /// Where each of the current stacks should go, on which display.
    ///
    /// Call after `initialize()`, which is what fills `activeMode`.
    public func stackLayout() -> [StackPlacement] {
        Geometry.layout(
            displays: displaySource.displays(), centres: activeMode, gap: config.gap)
    }

    /// The displays as the geometry sees them, for `debug geometry`.
    public func displays() -> [DisplayInfo] {
        displaySource.displays()
    }
}

/// Gap insets, ported from `Rectangle/WindowCalculation/GapCalculation.swift`.
public enum Gap {
    public struct Dimension: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let horizontal = Dimension(rawValue: 1 << 0)
        public static let vertical = Dimension(rawValue: 1 << 1)
        public static let both: Dimension = [.horizontal, .vertical]
        public static let none: Dimension = []
    }

    /// Which sides of a rect touch another placed window rather than the screen edge.
    public struct Edge: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let left = Edge(rawValue: 1 << 0)
        public static let right = Edge(rawValue: 1 << 1)
        public static let top = Edge(rawValue: 1 << 2)
        public static let bottom = Edge(rawValue: 1 << 3)
        public static let all: Edge = [.left, .right, .top, .bottom]
        public static let none: Edge = []
    }

    /// Insets `rect` by `size` on every side, then gives back half of it on each shared edge.
    ///
    /// The half is what makes the spacing uniform: two windows meeting at an interior boundary
    /// each give up half a gap there, so the space between them is one gap, the same as the gap
    /// at a screen edge. Without it the interior would be twice as wide as the border.
    ///
    /// It does not divide the leftover space evenly. For three columns of 3440 with a gap of 10
    /// it gives 1131.67, 1136.67, 1131.67 — the middle column has two shared edges and so gets
    /// half a gap back twice — where dividing `W - (n + 1) * gap` evenly would give three
    /// columns of 1133.33. Both fill the screen and both leave uniform gaps, and the first is
    /// what Rectangle Pro has actually put on this machine's screen, which is why
    /// `Geometry.layout` uses this and not the even division.
    public static func apply(
        to rect: CGRect,
        size: Int,
        dimension: Dimension = .both,
        sharedEdges: Edge = .none
    ) -> CGRect {
        let gap = CGFloat(size)
        let half = gap / 2

        var result = rect.insetBy(
            dx: dimension.contains(.horizontal) ? gap : 0,
            dy: dimension.contains(.vertical) ? gap : 0)

        if dimension.contains(.horizontal) {
            if sharedEdges.contains(.left) {
                result.origin.x -= half
                result.size.width += half
            }
            if sharedEdges.contains(.right) {
                result.size.width += half
            }
        }
        if dimension.contains(.vertical) {
            if sharedEdges.contains(.bottom) {
                result.origin.y -= half
                result.size.height += half
            }
            if sharedEdges.contains(.top) {
                result.size.height += half
            }
        }
        return result
    }
}

/// Where one stack's windows go.
public struct StackPlacement: Equatable, Sendable {
    /// Index into the stack list, matching `State.stacks`.
    public let stack: Int
    /// Index into the display list as given, so a caller can get back to the `DisplayInfo`.
    public let display: Int
    /// The centre x this stack was placed by, from `State.activeMode`.
    public let centreX: Int
    /// The target rect in AppKit's bottom-left space, inside the display's `visibleFrame`.
    public let frame: CGRect
    /// The same rect in the top-left space the Accessibility API and `CGWindowList` use.
    ///
    /// Both are carried because both are needed: `visibleFrame` arrives in the first and
    /// `AXUIElementSetAttributeValue` wants the second, and the only bug this whole type
    /// exists to prevent is handing one to something expecting the other.
    public let axFrame: CGRect

    public init(stack: Int, display: Int, centreX: Int, frame: CGRect, axFrame: CGRect) {
        self.stack = stack
        self.display = display
        self.centreX = centreX
        self.frame = frame
        self.axFrame = axFrame
    }
}

extension Geometry {

    /// Maps every stack to a display and a rect.
    ///
    /// `centres` is `State.activeMode`: one global x coordinate per stack, which is how stack
    /// membership is decided in the first place. A stack belongs to the display whose frame
    /// contains its centre, and the stacks landing on one display divide that display's
    /// `visibleFrame` between them, left to right, with gaps.
    ///
    /// Gaps come from `Gap.apply`, so a stack lands exactly where Rectangle would put the
    /// matching half or third. That is not the only option: dividing `W - (n + 1) * gap` evenly
    /// gives columns of the same width, where the shared-edge rule makes a middle column half a
    /// gap wider on each side. Both keep the gaps uniform and fill the screen.
    ///
    /// Rectangle's rule wins on a measurement rather than on taste. `spikot-wm debug ax` on the
    /// 3440x1440 display reports the three windows Rectangle Pro placed at
    /// `1131x1390@(10,40)`, `1137x1390@(1151,40)` and `1128x1383@(2302,44)`, which is this rule
    /// to the pixel; even columns would be 1133 wide and would shift all three on the first
    /// placement. With both tools in use during the migration, agreeing with the one already on
    /// screen matters more than three identical numbers.
    ///
    /// This replaces dividing the main display's width by `activeMode.count`
    /// (`Placer/main.swift:46-56`). That was wrong whenever a second display was attached:
    /// `computeModes` prepends an entry for the external monitor, so `twoColumns` reports
    /// three stacks and the arithmetic cut the *built-in* display into thirds while stack 0's
    /// windows were expected on the external one.
    public static func layout(
        displays: [DisplayInfo], centres: [Int], gap: Int
    ) -> [StackPlacement] {
        guard !displays.isEmpty, !centres.isEmpty else { return [] }
        let axis = flipAxis(displays)

        // Group the stacks by the display they fall on, keeping their original indices.
        var byDisplay: [Int: [(stack: Int, centreX: Int)]] = [:]
        for (stack, centreX) in centres.enumerated() {
            let display = displayIndex(containing: CGFloat(centreX), in: displays)
            byDisplay[display, default: []].append((stack, centreX))
        }

        var placements: [StackPlacement] = []
        for (display, members) in byDisplay {
            let visible = displays[display].visibleFrame
            // Left to right within the display, so column order follows the screen and not
            // the order the mode table happens to list.
            let ordered = members.sorted { $0.centreX < $1.centreX }
            let columnWidth = visible.width / CGFloat(ordered.count)

            for (column, member) in ordered.enumerated() {
                let raw = CGRect(
                    x: visible.minX + columnWidth * CGFloat(column), y: visible.minY,
                    width: columnWidth, height: visible.height)
                var shared: Gap.Edge = .none
                if column > 0 { shared.insert(.left) }
                if column < ordered.count - 1 { shared.insert(.right) }
                let frame = Gap.apply(to: raw, size: gap, sharedEdges: shared)
                placements.append(
                    StackPlacement(
                        stack: member.stack, display: display, centreX: member.centreX,
                        frame: frame, axFrame: flipped(frame, axis: axis)))
            }
        }
        return placements.sorted { $0.stack < $1.stack }
    }

    /// The display a window is on: the one it overlaps most.
    ///
    /// `rect` is in the Accessibility API's top-left coordinates, which is what `CGWindowList`
    /// reports, so it is flipped before being compared with the display frames. Largest overlap
    /// rather than "contains the origin": a window straddling two displays belongs to the one
    /// showing most of it, and a window dragged half off the screen still has an answer.
    public static func display(containingWindow rect: CGRect, in displays: [DisplayInfo]) -> Int {
        guard !displays.isEmpty else { return 0 }
        let inAppKitSpace = flipped(rect, axis: flipAxis(displays))
        let overlaps = displays.map { $0.frame.intersection(inAppKitSpace) }
        let areas = overlaps.map { $0.isNull ? 0 : $0.width * $0.height }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 {
            return best
        }
        // Off every display, which happens with a window on a monitor that has just been
        // unplugged. Nearest centre is the only remaining answer.
        return displayIndex(containing: inAppKitSpace.midX, in: displays)
    }

    /// The display a global x coordinate falls on.
    ///
    /// Falls back to the nearest display by centre distance rather than dropping the stack: a
    /// coordinate outside every display means a cache written under a different arrangement,
    /// and dropping a stack would renumber the ones after it.
    static func displayIndex(containing x: CGFloat, in displays: [DisplayInfo]) -> Int {
        if let index = displays.firstIndex(where: { $0.frame.minX <= x && x < $0.frame.maxX }) {
            return index
        }
        let nearest = displays.indices.min {
            abs(displays[$0].frame.midX - x) < abs(displays[$1].frame.midX - x)
        }
        logger.debug("Stack centre \(Int(x)) is on no display; using the nearest")
        return nearest ?? 0
    }
}
