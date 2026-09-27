import CoreGraphics
import Foundation

/// Where each window was before spikot-wm moved it, and what spikot-wm last did to it.
///
/// Ported from `Rectangle/WindowHistory.swift`, which is three dictionaries keyed by
/// `CGWindowID`. Two of them are here:
///
/// - `restoreRects`: the last frame the **user** set, so `restore` can put a window back.
/// - `lastActions`: what this project last did, which is what makes a repeated press cycle.
///
/// Rectangle's third, `preMaximizeRects`, is not ported. It exists only for
/// `RepeatedMaximizeRestore`, where pressing maximize a second time restores instead, and that is
/// gated on `repeatedMaximizeRestoresPrevious`, which is absent from the captured
/// `com.knollsoft.Hookshot` defaults and so off. A dictionary nothing reads is worse than no
/// dictionary.
///
/// **Not a multi-level undo stack**, and not persisted. One restore point per window, held in
/// memory by the agent: a window id is not predictably reused after a window closes, so a stale
/// restore rect would move a *different* window to a frame it never had. Nothing here survives an
/// agent restart, which is the honest cost of keying on window ids.
public final class WindowHistory {
    /// Frames the user set, by window number.
    public private(set) var restoreRects: [Int: CGRect] = [:]
    /// What the agent last did, by window number.
    public private(set) var lastActions: [Int: LastAction] = [:]

    public init() {}

    /// How many times this action has already been applied to this window in a row.
    public func repeats(of action: PlacementAction, window: Int) -> Int {
        LastAction.repeats(lastActions[window], for: action)
    }

    /// The frame `restore` should put the window back to.
    public func restoreRect(window: Int) -> CGRect? { restoreRects[window] }

    /// Records where a window was before an action moves it.
    ///
    /// Only when there is nothing recorded yet, or when the window is not where this project last
    /// put it — which means the user has moved or resized it since, making its current frame the
    /// one worth coming back to. That is Rectangle's rule at `WindowManager.swift:129-131`.
    public func noteFrameBeforePlacing(_ current: CGRect, window: Int) {
        let ours = lastActions[window]?.rect
        let movedExternally = ours.map { !$0.equalTo(current) } ?? false
        if restoreRects[window] == nil || movedExternally {
            restoreRects[window] = current
        }
    }

    /// Records what was just done, and the frame it produced.
    public func note(_ action: PlacementAction, window: Int, resulting rect: CGRect) {
        lastActions[window] = LastAction.advancing(lastActions[window], with: action, rect: rect)
    }

    /// Drops entries for windows that no longer exist.
    ///
    /// Without this the dictionaries grow for as long as the agent runs, and a window id reused by
    /// the window server would inherit a dead window's restore point.
    public func prune(keeping live: Set<Int>) {
        restoreRects = restoreRects.filter { live.contains($0.key) }
        lastActions = lastActions.filter { live.contains($0.key) }
    }

    /// One line per window, for `spikot-wm debug history`.
    public func report() -> [String] {
        let windows = Set(restoreRects.keys).union(lastActions.keys).sorted()
        return windows.map { window in
            let restore = restoreRects[window].map(Self.describe) ?? "-"
            let last = lastActions[window]
            let action = last.map { "\($0.action) x\($0.count)" } ?? "-"
            return "\(window)\trestore \(restore)\tlast \(action)"
        }
    }

    static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.width))x\(Int(rect.height))@(\(Int(rect.minX)),\(Int(rect.minY)))"
    }
}
