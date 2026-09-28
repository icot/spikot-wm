# Keybindings

Every binding this project owns, and what is still outstanding. **skhd is retired**: its
twelve `skhdrc` lines are commented out, the binary is uninstalled, and eleven of the bindings
now run in the agent — four `focus` and seven `exec`.

**Rectangle Pro is unbound** as of 2026-09-28: its thirteen placement shortcuts are cleared and
its login item is off, though the application itself stays installed (`spikot-win-1iz.1`).
Retiring skhd and retiring Rectangle were separate jobs — skhd held the four focus keys and eight
command lines, Rectangle's thirteen were in neither — so the placement work (`spikot-win-80o`)
never stood in the way.

## In the agent: focus

`Config.defaultHotkeys` ships these, so they work as soon as `hotkeysEnabled` is true.

| Key | Command |
|---|---|
| `alt-h` | `focus left` |
| `alt-l` | `focus right` |
| `alt-j` | `focus down` |
| `alt-k` | `focus up` |

## In the agent: commands

An `exec` binding runs an argument vector, which is what the remaining `skhdrc` lines were.
Three are left in `hotkeys` in `~/.config/spikot-wm/config.json`; the four launcher keys that
used to be here now use `launch`, below.

```json
{
  "cmd-shift-e": "exec emacsclient -c -n",
  "cmd-shift-g": "exec open -n /Applications/Ghostty.app",
  "cmd-p": "exec open /Applications/Ghostty.app -n --args -e ~/.local/bin/choosepass fzf"
}
```

Two notes on it:

- `cmd-p` has its path corrected. The `skhdrc` line points at `~/bin/choosepass`, but the
  script is at `~/.local/bin/choosepass`; the move from `~/bin` missed it, so that binding has
  been doing nothing. Registered as written it now reports **command not found** in the menu
  bar instead.
- `emacsclient` and `open` are named without a path on purpose: `execPath` puts `~/.local/bin`
  and `/opt/homebrew/bin` ahead of the system directories, and the child is given the same list
  as its `PATH`, so a script a binding runs can itself call `spikot-wm`, `rg` or `choose` by
  bare name. A LaunchAgent's own `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`, so none of those
  would be found otherwise.

## In the agent: launch

Moved off `mylauncher` in v0.28.0. These four are what the `exec mylauncher` lines became:

```json
{
  "cmd-f": "launch Firefox",
  "cmd-g": "launch Ghostty",
  "cmd-e": "launch Emacs",
  "cmd-s": "launch Safari"
}
```

`cmd-g` loses mylauncher's `fast` argument: with several windows `launch` shows the picker rather
than silently taking the first, which is what `fast` suppressed. Return on the highlighted row is
the same outcome with one keystroke more.

`~/.local/bin/mylauncher` and `Contrib/mylauncher.sh` are still on disk and no binding calls
either. Since v0.28.0 `spikot-wm list` defaults to tsv, so running the script by hand now reads
the wrong field and fails; `--format legacy` still produces the three fields it expects.

**The picker works from a hotkey**, confirmed on v0.27.5 with several windows of one application.
It does *not* take keys when opened over the socket — `spikot-wm pick` from a shell — because
macOS refuses activation to an application the user has not interacted with; such a panel
dismisses itself after 0.4s rather than sitting there unclosable. So bind `pick` to a key rather
than calling it from scripts. `alt-v` was meant to be that key and is still unbound.

## In the agent: place

These replace Rectangle Pro's thirteen. `cmd-shift-up` and `cmd-shift-down` name `top-half` and
`bottom-half`: `top` and `bottom` are not actions, and a wrong action registers cleanly and fails
only in the log until `spikot-win-80o.9` lands.

```json
{
  "cmd-shift-1": "place left-half",
  "cmd-shift-2": "place right-half",
  "cmd-shift-3": "place first-third",
  "cmd-shift-4": "place center-third",
  "cmd-shift-5": "place right-third",
  "cmd-shift-6": "place first-two-thirds",
  "cmd-shift-7": "place last-two-thirds",
  "cmd-shift-up": "place top-half",
  "cmd-shift-down": "place bottom-half",
  "cmd-alt-f": "place maximize"
}
```

Not yet bound: `next-display` and `previous-display`, which Rectangle held on `ctrl-shift-right`
and `ctrl-shift-left`, and `restore`, which takes no argument (`"ctrl-alt-backspace": "place
restore"`).

`choosewindow`, which `alt-v` pointed at, exists nowhere on the machine: it was the picker that was
never written, so that key has done nothing for a long time. `pick` is its replacement.

## Rectangle Pro's thirteen

Read from `defaults read com.knollsoft.Hookshot` and decoded in
`rectangle-pro-defaults.txt`. Rectangle holds these itself, which is why none of them was
needed to switch skhd off.

**All thirteen commands exist as of v0.25.0**, so these are valid config lines. What has not been
done is the side-by-side comparison against Rectangle on the same window, which is blocked on the
machine's Accessibility API; see `manual-tests.org`. Until that passes, moving a key over means
giving up Rectangle's version of it, so unbind them in Rectangle one at a time rather than all at
once. `spikot-win-1iz.1` is the uninstall.

| Key | Rectangle action | Binding |
|---|---|---|
| `cmd-shift-1` | `leftHalf` | `place left-half` |
| `cmd-shift-2` | `rightHalf` | `place right-half` |
| `cmd-shift-up` | `topHalf` | `place top-half` |
| `cmd-shift-down` | `bottomHalf` | `place bottom-half` |
| `cmd-alt-f` | `maximize` | `place maximize` |
| `cmd-shift-3` | `firstThird` | `place first-third` |
| `cmd-shift-4` | `centerThird` | `place center-third` |
| `cmd-shift-5` | `lastThird` | `place last-third` |
| `cmd-shift-6` | `firstTwoThirds` | `place first-two-thirds` |
| `cmd-shift-7` | `lastTwoThirds` | `place last-two-thirds` |
| `ctrl-shift-right` | `nextDisplay` | `place next-display` |
| `ctrl-shift-left` | `previousDisplay` | `place previous-display` |
| `ctrl-alt-delete` | `restore` | `place restore` |

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

Bear in mind that this makes the config file executable content, exactly as `skhdrc` was. It
buys no privilege — the agent runs as you, so a binding can do what you can do at a shell —
but it is a reason to keep the file to yourself.
