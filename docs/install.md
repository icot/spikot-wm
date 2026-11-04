# Installing with Homebrew

Releases are prebuilt for Apple Silicon and need macOS 26 or later. To build from source
instead, see Installation in the [README](../README.md).

## Install

```bash
brew tap icot/spikot-wm https://github.com/icot/spikot-wm
brew install icot/spikot-wm/spikot-wm
brew services start spikot-wm
```

This installs the `spikot-wm` CLI on `PATH` and the agent, `SpikotWM.app`, into the formula's
prefix. `brew services start` registers the agent to start at login and starts it now.

The install command names the formula in full. Homebrew 7 asks you to trust formulae from
third-party taps (`brew trust`), and installing by the full name trusts this one.

## Accessibility

On its first start the agent asks for Accessibility. Grant it to `SpikotWM` in System
Settings > Privacy & Security > Accessibility, then restart the agent, since a grant takes
effect at the next launch:

```bash
brew services restart spikot-wm
spikot-wm doctor
```

`doctor` should report `agent [ok] running, ... bundle org.traf.spikot-wm`. Its own
`accessibility` line is about the terminal you ran it from, and can fail without affecting the
agent.

The grant follows the app's bundle identifier and signature rather than its path, so it
survives upgrades, which move the app to a new directory under `Cellar`.

## Configuration

The agent reads `~/.config/spikot-wm/config.json`; `spikot-wm config` shows the effective
settings. Hotkeys are off until `hotkeysEnabled` is set, from the menu bar item or in the
file. The README covers the configuration and the hotkey syntax.

## Upgrade

```bash
brew update
brew upgrade spikot-wm
brew services restart spikot-wm
```

`brew upgrade` does not restart the agent: the old one keeps running from the removed version
until it is restarted. `spikot-wm doctor` shows both versions when they differ.

## Logs

```bash
brew services info spikot-wm
tail -f "$(brew --prefix)/var/log/spikot-wm/agent.err.log"
```

The agent logs to `agent.err.log`; `agent.log` stays mostly empty. The first line of
`agent.err.log` can be `sandbox_extension_issue_file_to_process failed for
.../SpikotWM.app: 1 (Operation not permitted)`, which the agent runs fine after.

## Moving from a source install

An agent installed with `make install-agent` and one started by `brew services` would contend
for the same socket. Remove the source install first:

```bash
make uninstall-agent      # stops and unregisters org.traf.spikot-agent
make uninstall            # removes ~/.local/bin/spikot-wm and ~/Applications/SpikotWM.app
```

`make uninstall` matters as well as `uninstall-agent`: `~/.local/bin` usually comes before
Homebrew's `bin` on `PATH`, so a leftover `spikot-wm` there would shadow the new one. The
configuration and the Accessibility grant carry over, because both builds use the same bundle
identifier and signing requirement.

## Uninstall

```bash
brew services stop spikot-wm
brew uninstall spikot-wm
brew untap icot/spikot-wm
```

This leaves `~/.config/spikot-wm/`, `~/.spikot-wm-state.json`, the logs under
`$(brew --prefix)/var/log/spikot-wm/` and the `SpikotWM` entry in the Accessibility list.
Remove those by hand if you want them gone.
