# Keybindings

Every binding this project owns, and what is still outstanding. **skhd is retired**: its
twelve `skhdrc` lines are commented out, the binary is uninstalled, and eleven of the bindings
now run in the agent — four `focus` and seven `exec`.

Retiring skhd and retiring Rectangle Pro were separate jobs. skhd held the four focus keys and
eight command lines; Rectangle holds thirteen placement shortcuts, none of which were in
`skhdrc`, so the placement work (`spikot-win-80o`) never stood in the way.

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
This is the block now in `hotkeys` in `~/.config/spikot-wm/config.json`:

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

Two notes on it:

- `cmd-p` has its path corrected. The `skhdrc` line points at `~/bin/choosepass`, but the
  script is at `~/.local/bin/choosepass`; the move from `~/bin` missed it, so that binding has
  been doing nothing. Registered as written it now reports **command not found** in the menu
  bar instead.
- `mylauncher` is named without a path on purpose, and so are `emacsclient` and `open`:
  `execPath` puts `~/.local/bin` and `/opt/homebrew/bin` ahead of the system directories, and
  the child is given the same list as its `PATH`, which `mylauncher` needs because it calls
  `spikot-wm`, `rg` and `choose` by bare name. A LaunchAgent's own `PATH` is
  `/usr/bin:/bin:/usr/sbin:/sbin`, so none of those would be found otherwise.

## Ready to move off mylauncher

`launch` exists as of v0.26.0 and the picker as of v0.27.0, so the four `exec mylauncher` lines
above can become these, and `alt-v` can finally have the job it was always meant to do:

```json
{
  "cmd-f": "launch Firefox",
  "cmd-g": "launch Ghostty",
  "cmd-e": "launch Emacs",
  "cmd-s": "launch Safari",
  "alt-v": "pick"
}
```

`cmd-g` loses mylauncher's `fast` argument: with several windows `launch` shows the picker rather
than silently taking the first, which is what `fast` suppressed. Return on the highlighted row is
the same outcome with one keystroke more.

Two things to know before moving these over:

- **The picker's keyboard handling is unverified.** The panel draws, but it never became the key
  window when opened over the socket — including from a bundle started by launchd, which was the
  leading explanation and turned out not to be it. What is left untried is the case these bindings
  actually use: a hotkey press, which is user input where a socket write is not. Until that is
  tried, `launch` on an application with several windows may put up a panel that only a click
  elsewhere will dismiss, and the agent logs a warning saying so. `launch` on an application with
  one window, and on one that is not running, are both verified. See `manual-tests.org`.
- **Delete `~/.local/bin/mylauncher` only once these bindings work.** It reads field 3 of
  `spikot-wm list` and hands it to `focus --window`, and that contract cannot be corrected while
  anything still depends on it (`spikot-win-9ic.3`).

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
