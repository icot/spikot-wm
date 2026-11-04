# Installs a prebuilt release rather than building from source, so installing needs no Swift
# toolchain. A formula rather than a cask: Homebrew quarantines cask downloads, and SpikotWM.app
# is ad-hoc signed and not notarized, so Gatekeeper would refuse to open it. Formula downloads
# are not quarantined.
#
# url and sha256 are rewritten by Contrib/release.sh for each release.
class SpikotWm < Formula
  desc "Tiling window manager for macOS that arranges windows in columnar stacks"
  homepage "https://github.com/icot/spikot-wm"
  url "https://github.com/icot/spikot-wm/releases/download/v0.32.0/spikot-wm-0.32.0-macos-arm64.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  def install
    bin.install "bin/spikot-wm"
    # The agent's Accessibility grant follows the bundle identifier and the identifier-only
    # signing requirement, not the path, so it survives the keg moving on each upgrade.
    prefix.install "SpikotWM.app"
  end

  # Must match InstallLayout.agentLogs in Sources/StateCore/install.swift.
  service do
    run [opt_prefix/"SpikotWM.app/Contents/MacOS/spikot-agent"]
    keep_alive true
    log_path var/"log/spikot-wm/agent.log"
    error_log_path var/"log/spikot-wm/agent.err.log"
  end

  def caveats
    <<~EOS
      The agent needs Accessibility. On its first start it asks for it; grant it to
      SpikotWM.app in System Settings > Privacy & Security > Accessibility, then run
        brew services restart spikot-wm

      brew upgrade does not restart the agent. After upgrading, run
        brew services restart spikot-wm

      If the agent was installed from source with `make install-agent`, remove that first
      with `make uninstall-agent`: two agents would contend for the same socket.
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/spikot-wm --version").strip
  end
end
