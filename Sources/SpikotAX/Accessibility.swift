import Cocoa

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
    /// TCC keys on the executable path and its code signature, so a rebuilt binary is a
    /// different principal and loses the grant. A process launched by another process
    /// inherits the responsible process's grant, which is why `spikot-wm` works today
    /// when skhd started it. See spikot-win-m7t.1.
    public static let grantInstructions = """
        Grant Accessibility in System Settings > Privacy & Security > Accessibility.
        The permission is tied to the executable path and its signature, so a rebuilt
        binary needs granting again; installing to a stable path avoids that.
        """
}
