# spikot-wm

"Window Manager" for macOS. Intends to manage windows in tiled stacks.

## What works (run `spikot-wm --version` for the current version):

- Works for a hardcoded mode (two* or three* columnar stacks)
- Supports one external monitor, plugged to the right of a laptop (guess my setup)
- Detect and manage properly new windows and window deletions

[*] If a external monitor is plugged, the mode name refers to the number of stacks in the main (external)
screen. The laptop display holds one additional stack

## Limitations

- Actual window placing is not implemented and depends on external tools (Rectangle)
- Keybinding functionality is implemented via wrapper scripts keybinded via shkbd

## My workflow

- I manually place windows in selected "stacks" using Rectangle Pro
- Keybindings for Rectagle are defined in Rectangle itself
- spikot-wm offers functionality to select windows based on relative stack postitions and to
switch focus to them. This is used via shkbd key bindings
- I have a custom bash script (mylauncher) which switches
  automatically to selected applications windows if they exist,
  independent of screen location, and launches a new window of said
  application if not currently active

## Approach

- Single pass process of open, visible windows to match to stacks location
- Stack membership cached between executions

## Next steps

- At high level, ideally implement all functionality here, simplifying
  as much as possible 3rd party dependencies, by maybe:
  - Integrating keybindings management
  - Integrating the mylauncher script functionality
  - Performing window placing without rectangle
- Add a little gui, in the form of a mac bar permanent icon to offer
  direct access to manage the configuration

## Installation

### Requirements

- macOS 26 or later
- The Swift 6.2 toolchain. The Command Line Tools are enough; Xcode is not needed.
  Check with `swift --version`
- `swiftlint` only for `make lint`, via Homebrew

### Build and install

```sh
make build                 # debug build into .build/debug
make release               # release build

make install               # spikot-wm and spikot-placer into ~/.local/bin
make install prefix=/usr/local   # somewhere else

make install-app           # SpikotWM.app into ~/Applications
make install-agent         # and register it to start at login
```

`make install-app` builds the agent bundle and `make install-agent` registers it as a
LaunchAgent, writing logs to `~/Library/Logs/spikot-wm/`. They are separate steps so the
bundle can be tried by hand first:

```sh
open ~/Applications/SpikotWM.app
```

Make sure `~/.local/bin` is on `PATH`. The skhd LaunchAgent already puts it there for
anything launched from a keybinding, but a login shell may not.

### Accessibility permission

Everything that moves, raises or reads a window needs it, and the agent asks for it on
first launch. Grant it in System Settings > Privacy & Security > Accessibility, then
restart the agent: a granted permission takes effect for the next launch, not the current
one.

```sh
spikot-wm doctor           # permissions, config, displays, cache, and the agent
```

`doctor` asks the running agent about itself over the socket, which is the only way to get
a correct answer: see below.

Two things about how macOS handles this are worth knowing, because they make the
permission look inconsistent otherwise.

A permission is attributed to the **responsible process**, not to the binary that runs. A
command started from a terminal inherits the terminal's grant, and one started from a
keybinding inherits skhd's. So `spikot-wm` reports itself trusted from a shell while
holding no grant of its own. The agent is different: as a LaunchAgent it is its own
responsible process, which is why it has to ask, and why `SpikotWM` is the only part of
this project that appears in the Accessibility list.

This is also why `doctor` asks the agent rather than checking locally, and why running
`spikot-agent --check-permissions` from a terminal cannot answer the question: started from
a shell it inherits the shell's grant and reports that instead of its own. Its answer is
only meaningful when launchd started it, which is what `doctor` reads.

The grant survives rebuilds. `make bundle` signs with an identifier-only designated
requirement, so the identity does not change when the binary does. A plain ad-hoc
signature would pin the requirement to the binary hash and lose the grant on every build.

**Screen Recording is not required.** It would only affect `kCGWindowName`; window titles
come from the Accessibility API instead.

### Configuration

`~/.config/spikot-wm/config.json`, created on demand. Every key is optional, so the file
only needs what differs from the defaults and `{}` is valid.

```sh
spikot-wm config           # effective settings, and whether a file was found
```

`SPIKOT_CONFIG` points at a different file, and `SPIKOT_GAP`, `SPIKOT_MODE`,
`SPIKOT_CACHE_PATH`, `SPIKOT_USE_CACHE` and `SPIKOT_LOG` override single values for one
run. The menu bar item edits the settings changed most often and writes them to the same
file.

### Hotkeys

The agent can hold the keys itself, instead of a separate hotkey daemon. Bindings are
config entries whose value is a `spikot-wm` command:

```json
{
  "hotkeysEnabled": true,
  "hotkeys": {
    "alt-h": "focus left",
    "alt-l": "focus right",
    "cmd-shift-return": "state"
  }
}
```

`-` and `+` both separate, and whitespace around them is ignored, so a line moved over
from `skhdrc` (`cmd + shift - e`) parses as it stands. Modifiers are `cmd`, `alt` (or
`opt`), `ctrl` and `shift`; at least one is required, since a binding with none would take
that key away from every application. Key names are letters, digits, `f1`–`f20`, the arrow
keys, and names such as `return`, `space`, `escape`, `delete` and `minus`.

**`hotkeysEnabled` is false by default**, so installing the agent cannot take keys away
from whatever holds them today. The menu bar item has the toggle and lists every binding
with what became of it: registered, not understood, or a repeat of another line. A binding
naming a command the agent does not answer is reported there rather than failing on the
keypress.

One thing the agent cannot tell you: if another application already holds a combination,
registering it still succeeds and the key simply never arrives. So while skhd binds
`alt-h`, skhd keeps winning and the agent's binding lies dormant — which is what makes the
migration one key at a time rather than all at once.

### Verifying

```sh
spikot-wm list             # one line per window
spikot-wm state            # stack membership
spikot-wm list --explain   # writes "served by: agent" or "in-process" to stderr
spikot-wm debug ax         # how each window maps to its Accessibility element
```

The agent is an optimisation, not a requirement: with it stopped, every command runs in
the process instead, so nothing breaks if it is not installed or has crashed.
`--no-daemon` forces that path.

### Uninstalling

```sh
make uninstall-agent       # unregister the LaunchAgent
make uninstall             # that, plus the binaries and the bundle
```

Neither removes `~/.config/spikot-wm/config.json`, `~/.spikot-wm-state.json` or the
Accessibility grant; delete those by hand if you want them gone.

### Keybindings

Not built in yet. Bindings currently go through [skhd](https://github.com/koekeishiya/skhd)
or any launcher that can run a command:

```
alt - h : ~/.local/bin/spikot-wm focus left
alt - l : ~/.local/bin/spikot-wm focus right
alt - j : ~/.local/bin/spikot-wm focus down
alt - k : ~/.local/bin/spikot-wm focus up
```
