# Keybindings

Every binding this project intends to own, what holds it today, and what it needs from
spikot-wm. `~/.config/skhd/skhdrc` has twelve lines; eleven of them can move now.

Retiring skhd and retiring Rectangle Pro are separate jobs. skhd holds the four focus keys
and eight command lines; Rectangle holds thirteen placement shortcuts and none of them are in
`skhdrc`. So the placement work (`spikot-win-80o`) does not stand in the way of switching skhd
off.

## Moved already

`Config.defaultHotkeys` ships these, so they work as soon as `hotkeysEnabled` is true.

| Key | Command |
|---|---|
| `alt-h` | `focus left` |
| `alt-l` | `focus right` |
| `alt-j` | `focus down` |
| `alt-k` | `focus up` |

## Ready to move, with `exec`

An `exec` binding runs an argument vector, which is what the remaining `skhdrc` lines are.
Paste this into `hotkeys` in `~/.config/spikot-wm/config.json`:

```json
{
  "cmd-shift-e": "exec emacsclient -c -n",
  "cmd-shift-g": "exec open -n /Applications/Ghostty.app",
  "cmd-p": "exec open /Applications/Ghostty.app -n --args -e ~/.local/bin/choosepass fzf",
  "cmd-f": "exec mylauncher Firefox",
  "cmd-g": "exec mylauncher Ghostty fast",
  "cmd-e": "exec mylauncher Emacs",
  "cmd-s": "exec mylauncher Safari"
}
```

Two notes on that block:

- `cmd-p` has its path corrected. The `skhdrc` line points at `~/bin/choosepass`, but the
  script is at `~/.local/bin/choosepass`; the move from `~/bin` missed it, so that binding has
  been doing nothing. Registered as written it now reports **command not found** in the menu
  bar instead.
- `mylauncher` is named without a path on purpose, and so are `emacsclient` and `open`:
  `execPath` puts `~/.local/bin` and `/opt/homebrew/bin` ahead of the system directories, and
  the child is given the same list as its `PATH`, which `mylauncher` needs because it calls
  `spikot-wm`, `rg` and `choose` by bare name. A LaunchAgent's own `PATH` is
  `/usr/bin:/bin:/usr/sbin:/sbin`, so none of those would be found otherwise.

`spikot-win-9ic.1` replaces the four `mylauncher` lines with a native `launch` command, and
`9ic.3` retires the script.

## Not moving yet

| Key | Today | Waiting for |
|---|---|---|
| `alt-v` | `~/.local/bin/choosewindow` | `spikot-win-9ic.2`, the window picker |

`choosewindow` exists nowhere on the machine: it was the picker that was never written, so this
key has done nothing for a long time. Leave it unbound until the native panel lands.

## Rectangle Pro's thirteen

Read from `defaults read com.knollsoft.Hookshot` and decoded in
`rectangle-pro-defaults.txt`. Rectangle holds these itself, so nothing here is needed to
switch skhd off — they matter when Rectangle is retired (`spikot-win-1iz.1`). The command
column is what the binding will say; the exact spelling is settled by the bead that implements
it, so these are not yet valid config lines.

| Key | Rectangle action | Implemented by |
|---|---|---|
| `cmd-shift-1` | `leftHalf` | `spikot-win-80o.3` |
| `cmd-shift-2` | `rightHalf` | `spikot-win-80o.3` |
| `cmd-shift-up` | `topHalf` | `spikot-win-80o.3` |
| `cmd-shift-down` | `bottomHalf` | `spikot-win-80o.3` |
| `cmd-alt-f` | `maximize` | `spikot-win-80o.3` |
| `cmd-shift-3` | `firstThird` | `spikot-win-80o.4` |
| `cmd-shift-4` | `centerThird` | `spikot-win-80o.4` |
| `cmd-shift-5` | `lastThird` | `spikot-win-80o.4` |
| `cmd-shift-6` | `firstTwoThirds` | `spikot-win-80o.4` |
| `cmd-shift-7` | `lastTwoThirds` | `spikot-win-80o.4` |
| `ctrl-shift-right` | `nextDisplay` | `spikot-win-80o.5` |
| `ctrl-shift-left` | `previousDisplay` | `spikot-win-80o.5` |
| `ctrl-alt-delete` | `restore` | `spikot-win-80o.6` |

`cmd-shift-4` is also the system screenshot shortcut. Measured: registering it succeeds and
reports no conflict, which says nothing about who receives the key — a clash is undetectable
either way. Which side wins is unverified, so expect to need another key when `80o.4` lands.

## Syntax

`-` and `+` both separate, and whitespace around them is ignored, so an `skhdrc` line such
as `cmd + shift - e` parses as it stands.

- Modifiers: `cmd`/`command`, `alt`/`opt`/`option`, `ctrl`/`control`, `shift`. At least one
  is required; a binding with none would take that key from every application.
- Keys: `a`–`z`, `0`–`9`, `f1`–`f20`, `left`/`right`/`up`/`down`, and `return`, `space`,
  `tab`, `escape`, `delete`, `forwarddelete`, `home`, `end`, `pageup`, `pagedown`, `help`,
  `minus`, `equal`, `grave`, `leftbracket`, `rightbracket`, `semicolon`, `quote`, `comma`,
  `period`, `slash`, `backslash`. Aliases such as `esc`, `enter`, `pgup` and `uparrow` also
  work.
- `fn` cannot be part of a binding: `RegisterEventHotKey` takes the four Carbon modifier
  bits and `fn` is not one of them.
- The value is either a `spikot-wm` command — a bare argument goes where that command wants
  it, so `focus left` means `--target left` — or `exec` followed by a command line.

### exec

No shell. Whitespace separates arguments; single and double quotes group, and inside them
everything is literal, so an empty argument is written `""`. There is no backslash escaping,
no globbing, no `$VAR` and no pipes; a binding that needs any of those can name a script.

A command containing a `/` is a path, with a leading `~` expanded. Anything else is looked up
in `execPath`, and a command that cannot be found is reported in the menu bar when the binding
is registered rather than failing silently when the key is pressed. The command's own output
goes to the agent's log in `~/Library/Logs/spikot-wm/`, and a non-zero exit is logged there
too.

Bear in mind that this makes the config file executable content, exactly as `skhdrc` is. It
buys no privilege — the agent runs as you, so a binding can do what you can do at a shell —
but it is a reason to keep the file to yourself.
