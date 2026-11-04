import Cocoa
import CoreGraphics

/// Accessibility permission, which every window move and window raise depends on.
///
/// Replaces the old `checkAccess()`, which had no call sites, printed to stdout, and
/// always passed `kAXTrustedCheckOptionPrompt: true` so any call popped the system
/// dialog. Checking and asking are separate here, because `spikot-wm doctor` should be
/// able to report the state without putting a dialog on screen.
///
/// Lives in SpikotAX rather than StateCore because it is purely an Accessibility concern.
public enum Accessibility {

    /// Whether this process may use the Accessibility API. Does not prompt.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system permission dialog when not already trusted.
    ///
    /// Returns trust as it stands now, which is almost always false on the first call:
    /// granting happens in System Settings and takes effect for the *next* launch.
    @discardableResult
    public static func requestTrust() -> Bool {
        // AXUIElement.h declares kAXTrustedCheckOptionPrompt as a non-const
        // `extern CFStringRef`, so Swift 6 imports it as a mutable global and rejects
        // reading it. Its documented value is used directly.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// What to tell someone whose permission is missing.
    ///
    /// TCC attributes a check to the responsible process. The agent is its own, and as
    /// SpikotWM.app its grant follows the bundle identifier and the identifier-only designated
    /// requirement `make bundle` signs with, so a rebuild keeps it; a bare binary is keyed on its
    /// cdhash and loses it on every rebuild. A command run from a terminal without the agent
    /// borrows the terminal's grant. See spikot-win-m7t.1.
    public static let grantInstructions = """
        Grant Accessibility in System Settings > Privacy & Security > Accessibility: to
        SpikotWM.app for the agent, or to the terminal for commands run without the agent.
        """
}

/// Screen Recording, which `CGWindowListCopyWindowInfo` needs before it will fill in
/// `kCGWindowName`.
///
/// spikot-wm does **not** require this. Window titles come from `kAXTitle`
/// (`WindowIdentity.title(of:)`), which needs only Accessibility. Measured on this machine:
/// `CGPreflightScreenCaptureAccess()` is false and every window's `kCGWindowName` is nil,
/// while `kAXTitle` returns the real titles. The check exists so `doctor` can say whether
/// the cheaper CGWindowList path is available, not so anything can demand the permission.
public enum ScreenRecording {

    /// Whether `kCGWindowName` will be populated. Does not prompt.
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts for Screen Recording.
    ///
    /// Not called anywhere. Asking for a permission that is not needed trains people to
    /// click through prompts, and this one adds a System Settings entry that cannot be
    /// removed from the app side. Left here so the decision is visible rather than absent.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
