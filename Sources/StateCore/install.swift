// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How this copy of spikot-wm was installed, so that advice names commands that apply to it.
///
/// `make install-agent` puts the agent in `~/Applications/SpikotWM.app` under the LaunchAgent
/// `org.traf.spikot-agent`, logging to `~/Library/Logs/spikot-wm`. The Homebrew formula puts it
/// in the keg and runs it with `brew services`, which labels the LaunchAgent itself and logs
/// where the formula's `service` block says.
public enum InstallLayout: Equatable, Sendable {
    /// Built from the repository with make.
    case source
    /// Installed by the Homebrew formula into the prefix `prefix`, e.g. `/opt/homebrew`.
    case homebrew(prefix: String)

    /// The layout of the running executable.
    public static var current: InstallLayout {
        detect(executablePath: Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "")
    }

    /// Homebrew installs into `<prefix>/Cellar/spikot-wm/<version>`. Its `bin/spikot-wm` and
    /// `opt/spikot-wm` are symlinks into that, so the path has to be resolved before it gets here.
    public static func detect(executablePath: String) -> InstallLayout {
        guard let keg = executablePath.range(of: "/Cellar/spikot-wm/") else { return .source }
        return .homebrew(prefix: String(executablePath[..<keg.lowerBound]))
    }

    /// The command that starts the agent and keeps it running across logins.
    public var startAgent: String {
        switch self {
        case .source: "make install-agent"
        case .homebrew: "brew services start spikot-wm"
        }
    }

    /// The command that replaces a running agent with the installed version.
    public var restartAgent: String {
        switch self {
        case .source: "make install-agent"
        case .homebrew: "brew services restart spikot-wm"
        }
    }

    /// The command that shows the agent's LaunchAgent: whether it is loaded, its pid and its
    /// last exit status. For Homebrew it is `brew services info` rather than `launchctl print`,
    /// because the label is Homebrew's to choose: it was `homebrew.mxcl.<formula>` and Homebrew 7
    /// names it `sh.brew.<formula>`.
    public var agentStatus: String {
        switch self {
        case .source: "launchctl print gui/$(id -u)/org.traf.spikot-agent"
        case .homebrew: "brew services info spikot-wm"
        }
    }

    /// Where the agent's stdout and stderr go. Must match the `service` block in
    /// Formula/spikot-wm.rb and the plist in Packaging/.
    public var agentLogs: String {
        switch self {
        case .source: "~/Library/Logs/spikot-wm/"
        case .homebrew(let prefix): "\(prefix)/var/log/spikot-wm/"
        }
    }
}
