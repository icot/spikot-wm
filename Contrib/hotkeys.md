# Keybindings

Every binding this project intends to own, what holds it today, and which command it needs.
The four that work are shipped as `Config.defaultHotkeys`; the rest are here rather than in
the default config because binding a command the agent does not answer produces a key that
reports itself broken in the menu bar.

To take one on, copy its line into `hotkeys` in `~/.config/spikot-wm/config.json` and set
`hotkeysEnabled` to `true`.

## Shipped

Bound by `~/.config/skhd/skhdrc` today, and by `Config.defaultHotkeys` once
`hotkeysEnabled` is on. While skhd still binds them it keeps them: its event tap runs
before Carbon delivery, and the clash is invisible to `RegisterEventHotKey`, so the cutover
is one key at a time — remove a line from `skhdrc`, restart skhd, and the agent's
registration starts arriving (`spikot-win-1k4.3`).

| Key | Command |
|---|---|
| `alt-h` | `focus left` |
| `alt-l` | `focus right` |
| `alt-j` | `focus down` |
| `alt-k` | `focus up` |

## Waiting on placement (`spikot-win-80o`)

The thirteen shortcuts **Rectangle Pro** holds, read from
`defaults read com.knollsoft.Hookshot` and decoded in `rectangle-pro-defaults.txt`. The
command column is what the binding will say; the exact spelling is settled by the bead that
implements it, so these are not yet valid config lines.

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

## Waiting on the launcher (`spikot-win-9ic`)

Bound by `skhdrc` to `~/.local/bin/mylauncher`, which finds the app's windows and focuses
one or launches it.

| Key | Today | Implemented by |
|---|---|---|
| `cmd-f` | `mylauncher Firefox` | `spikot-win-9ic.1` |
| `cmd-g` | `mylauncher Ghostty fast` | `spikot-win-9ic.1` |
| `cmd-e` | `mylauncher Emacs` | `spikot-win-9ic.1` |
| `cmd-s` | `mylauncher Safari` | `spikot-win-9ic.1` |
| `alt-v` | `~/.local/bin/choosewindow` | `spikot-win-9ic.2` |

Two more `skhdrc` lines are **not** carried over, because neither has worked for some time:

- `alt-v` points at `~/.local/bin/choosewindow`, which exists nowhere on the machine. It was
  the window picker that was never written; `spikot-win-9ic.2` is the replacement, so the key
  is listed above against that bead rather than dropped.
- `cmd-p` points at `~/bin/choosepass`, but the script is at `~/.local/bin/choosepass`. The
  move from `~/bin` to `~/.local/bin` missed it. Nothing in spikot-wm replaces a password
  picker, so this one belongs in `skhdrc` with the path corrected, or in whatever replaces
  skhd.

Left alone as well: `cmd+shift-e` (`emacsclient -c -n`) and `cmd+shift-g`
(`open -n /Applications/Ghostty.app`), which launch things directly and need nothing from a
window manager.

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
- The command is a `spikot-wm` command line. A bare argument goes where that command wants
  it (`focus left` means `--target left`), and anything else is written `--flag value` or
  `name=value`.
