# spikot-wm

"Window Manager" for macOS. Intends to manage windows in tiled stacks.

## What works (run `spikot-wm --version` for the current version):

- Works for a hardcoded mode (two* or three* columnar stacks)
- Supports one external monitor, plugged to the right of a laptop (guess my setup)
- Detect and manage properly new windows and window deletions

[*] If a external monitor is plugged, the mode name refers to the number of stacks in the main (external)
screen. The laptop display holds one additional stack

## Limitations

- Two* or three* columnar stacks only, and one external monitor positioned left or right

## My workflow

All of it runs in the agent now; the three external pieces this project started against are
gone or unbound.

- `place` puts windows in stacks and in Rectangle's halves, thirds and displays. Rectangle Pro
  is unbound and off the login items, still installed as a fallback
- Hotkeys are the agent's own. skhd is uninstalled
- `launch` and the picker replaced the `mylauncher` bash script, which nothing calls any more
- A menu bar item shows the bindings, the agent's state and the configuration

## Approach

- Single pass process of open, visible windows to match to stacks location
- Stack membership cached between executions

## Next steps

- Compare each placement against Rectangle Pro's own shortcut, pixel for pixel
  (`spikot-win-80o.8`)
- Reject a hotkey naming an action that does not exist when it is registered, rather than
  logging it on the keypress (`spikot-win-80o.9`)
- Rewrite these docs for the agent architecture (`spikot-win-1iz.3`)

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

make install               # the spikot-wm CLI into ~/.local/bin
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

Make sure `~/.local/bin` is on `PATH` for your own shell use. Commands run from a hotkey do
not depend on it: the agent resolves those against `execPath` (see Hotkeys below).

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
command started from a terminal inherits the terminal's grant, so `spikot-wm` reports itself
trusted from a shell while holding no grant of its own. A hotkey is different again: it runs
inside the agent, which does hold a grant of its own. The agent is different: as a LaunchAgent it is its own
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

The four stack-focus keys — `alt-h`, `alt-l`, `alt-j`, `alt-k` — ship in the defaults, the
same keys with the same meanings as the `skhd` bindings they replace.
`Contrib/hotkeys.md` lists every other binding this project means to own, with the command
each one needs and which version brings it.

A config file written before those defaults existed holds `"hotkeys": {}`, and an explicit
empty table is not the same as an absent one, so the defaults do not reach it. The menu bar
item offers **Hotkeys > Add the default bindings** in that case, which merges in what is
missing and leaves anything already there alone.

**`hotkeysEnabled` is false by default**, so installing the agent cannot take keys away
from whatever holds them today. The menu bar item has the toggle and lists every binding
with what became of it: registered, not understood, or a repeat of another line. A binding
naming a command the agent does not answer is reported there rather than failing on the
keypress.

One thing the agent cannot tell you: if something else already holds a combination,
registering it still succeeds and the key simply never arrives. An event tap, which is how
hotkey daemons such as skhd work, runs before Carbon delivery and keeps the keystroke. That is
what lets a migration go one key at a time rather than all at once — but it also means a
binding can be registered, listed as bound, and still never fire.

A binding can also run a command, which is what a hotkey daemon is mostly for:

```json
{
  "hotkeys": {
    "cmd-shift-e": "exec emacsclient -c -n",
    "cmd-shift-g": "exec open -n /Applications/Ghostty.app"
  }
}
```

No shell: whitespace separates arguments, single and double quotes group, and an empty
argument is written `""`. A command with a `/` in it is a path, with `~` expanded; anything
else is looked up in `execPath`, which defaults to `~/.local/bin`, `/opt/homebrew/bin`,
`/usr/local/bin` and the system directories, and is also the `PATH` the command itself is
given. That list exists because a LaunchAgent's `PATH` is only
`/usr/bin:/bin:/usr/sbin:/sbin`, so `emacsclient` and anything in `~/.local/bin` would
otherwise be invisible.

A command that cannot be found is reported in the menu bar as soon as the binding is
registered, rather than doing nothing when the key is pressed. Its output and any non-zero
exit go to `~/Library/Logs/spikot-wm/`.

`exec` makes the config file executable content, as `skhdrc` is. It grants nothing new — the
agent runs as you — but it is a reason to keep the file to yourself.

`choose` puts another program's output in the picker and runs a command with the line picked,
which is what `choose-gui` and `fzf` were used for:

```json
{
  "hotkeys": {
    "cmd-p": "choose choosepass list | pass show -c {}"
  }
}
```

Left of the `|` is a command whose standard output lines become the rows; right of it, the
command run with the picked line in place of every `{}`, or appended as the last argument when
there is no `{}`. It is not a shell pipe: only the picked line reaches the action. Both sides
follow the `exec` rules above, and both are looked up when the binding is registered. A quoted
`'|'` is an ordinary argument. The panel opens on the keypress and fills when the list command
finishes; one that runs longer than 10 seconds is stopped. Number keys type into the filter
here instead of picking a row, since the entries may contain digits.

Opening a terminal with `exec open -n Ghostty.app --args -e <script>` does not work for a
script that needs Homebrew tools: `open` starts the terminal through LaunchServices, which gives
it launchd's `PATH` rather than `execPath`.

### Launching

```sh
spikot-wm launch Firefox
```

No windows means start it, one means focus it, several means show the picker — a floating list of
`owner — title`, filtered as you type, with Up and Down, Return, Escape, and 1 to 9 to pick a row
outright. `spikot-wm pick` opens it for every window on screen, or for one application's with
`pick Firefox`.

The picker's colours come from the `picker` section of the config, read each time the panel
opens, so a `reload` changes them:

```json
{
  "picker": {
    "background": "#000000d9",
    "selection": "#ff78c6",
    "text": "#ffffff"
  }
}
```

Each value is `#RRGGBB` or `#RRGGBBAA`, with the `#` optional. Every key is optional too: a missing
one keeps the built-in colour, which is black at 85% opacity for the background, white for the
text, and the system accent colour behind the selected row. The "Type to filter" prompt is the
text colour at 65% of its opacity. A value that is not a colour fails the config load with the key
named, as an unknown `activeMode` does. The colours apply to the window picker and to `choose`.

The picker needs the agent, because it needs a run loop and key focus; without one, several windows
means the frontmost of them is focused, which is what the old `mylauncher <App> fast` did.

An application usually needs no configuration: `launch` looks for `<Name>.app` in
`/Applications`, `~/Applications` and the system application folders. The `launch` section of the
config is for the cases that needs, and ships knowing four:

```json
{
  "launch": {
    "Firefox": { "bundleID": "org.mozilla.firefox" },
    "Emacs": { "command": ["emacsclient", "-c", "-n", "-a", ""] }
  }
}
```

A `bundleID` survives a rename or a move where a name does not. A `command` is for an application
that is really a client of something already running: `emacsclient` opens a frame on the running
daemon instead of starting a second Emacs, and the empty `-a` stops it falling back to another
editor. Commands are resolved against `execPath`, as `exec` bindings are.

A config file written before those defaults existed holds `"launch": {}`, and an explicit empty
table is not an absent one, so the entries do not reach it — the same wrinkle as the hotkeys.

### Verifying

```sh
spikot-wm list             # one line per window
spikot-wm state            # stack membership
spikot-wm list --explain   # writes "served by: agent" or "in-process" to stderr
spikot-wm place 1                    # move the frontmost window to stack 1
spikot-wm place 1 --window 5964       # move that exact window, whatever is frontmost
spikot-wm place left-half            # also right-half, top-half, bottom-half, maximize
spikot-wm place first-third          # also center-third, last-third, and the two-thirds
spikot-wm place next-display         # also previous-display
spikot-wm place restore              # back to where the window was before spikot-wm moved it
spikot-wm launch Firefox             # focus its window, or start it if it has none
spikot-wm debug ax         # how each window maps to its Accessibility element
spikot-wm debug geometry   # the displays, and where each stack is placed on them
spikot-wm debug history    # what the agent remembers about each window
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
