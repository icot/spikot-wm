# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpikotWM is a tiling window manager for macOS that organizes windows into columnar stacks. It uses the macOS Accessibility API and CGWindowList to detect, track, and manage windows across displays.

The system operates through two main executables:
- `spikot-wm`: The core state management tool that tracks window positions and manages stack membership
- `spikot-placer`: The window placement tool that actually moves windows using the Accessibility API

## Build Commands

```bash
# Development build
swift build

# Release build
make release

# Install both CLI binaries to ~/.local/bin (default prefix)
make install

# Install to custom location
make install prefix=/usr/local

# Build the agent's .app bundle into .build/SpikotWM.app
make bundle

# Install the bundle to ~/Applications (override with appdir=)
make install-app

# Register the agent to start at login (logs to ~/Library/Logs/spikot-wm)
make install-agent
make uninstall-agent

# Remove installed binaries and the bundle
make uninstall

# Checks that make test cannot make live in manual-tests.org, with procedures and
# what counts as a pass. Update it when one moves from unverified to measured.

# Lint code (0 violations expected)
make lint

# Apply swiftlint's autocorrections
make lint-fix

# Release build from scratch, when an incremental one is not wanted
make release-clean

# Clean build artifacts
make clean
```

The project targets Swift 6.2 tooling in Swift 6 language mode (`swift-tools-version:
6.2`) and macOS 26+. It builds with the Command Line Tools toolchain alone — no Xcode
install is required.

`make lint` sets `DYLD_FRAMEWORK_PATH` from `xcode-select -p` because swiftlint dlopens
`sourcekitdInProc.framework` through a relative path that otherwise only resolves
against a full Xcode install.

`release` deliberately does not depend on `clean`. It used to, so `make install`,
`install-app` and `install-agent` each wiped `.build` and recompiled everything — about 33
seconds every time. With it gone, a no-op `make install` takes 0.92 s. Use `release-clean`
for a scratch build.

`build`, `release` and `test` pipe through a `sed` that drops the
`ld: warning: search path .../Developer/{Library/Frameworks,usr/lib} not found` lines.
SwiftPM asks for those paths assuming the Xcode layout; on a Command Line Tools install the
real directories are one level up and a clean release build prints nine of them. `sed`
rather than `grep -v` because `sed` exits 0 whatever it matches, so with `set -o pipefail`
the pipeline still reports a build failure. The pattern is narrow, so a genuine
`ld: warning` still reaches the terminal.

## Architecture

### State Management System

The core architecture revolves around a state caching system in `StateCore/state.swift`:

1. **Window Discovery**: Uses `CGWindowListCopyWindowInfo()` to enumerate all visible windows
2. **Stack Assignment**: Windows are assigned to stacks based on their horizontal position (coordX) relative to computed stack center points
3. **State Caching**: Current window-to-stack assignments are persisted to `~/.spikot-wm-state.json`
4. **Smart Merging**: On each run, the system:
   - Detects new windows (created since last run)
   - Detects closed windows (removed since last run)
   - Detects windows that moved between stacks
   - Merges cached state with current state to preserve stack membership

### Key Data Structures

- `Window` (types.swift): Full window metadata from CGWindowList
- `WindowMeta` (types.swift): Lightweight identifier for window equality checking
- `State` (state.swift): Main state container with caching logic
- `Config` (types.swift): Configuration for gap size, mode, cache path

### Stack Modes

Modes define horizontal divisions of screen space:
- `twoColumns`: Two stacks split at 1/4 and 3/4 of screen width
- `threeColumns`: Three stacks split at 1/6, 1/2, and 5/6 of screen width

If an external monitor is detected, stack 0 is placed on the external display (assumed to be positioned left or right of primary). The stack center points are computed dynamically in `computeModes()` based on `NSScreen.screens`.

### Window Placement

The `spikot-placer` tool (Placer/main.swift and Placer/winman.swift) uses the Accessibility API to move windows:

1. Queries window info via `CGWindowListCreateDescriptionFromArray()`
2. Gets the owning application's PID
3. Creates an `AXUIElement` for the application
4. Finds the window element by its `CGWindowID` via `_AXUIElementGetWindow`, falling back
   to comparing bounds within 2 points only when that does not answer
5. Sets new position and size via `AXUIElementSetAttributeValue()`

`spikot-wm debug ax` prints, per window, which of the two paths matched and whether the
Accessibility frame and the CGWindowList bounds agree. Note the two disagree about the y
axis: Accessibility and CGWindowList use a top-left origin, `NSScreen.frame` a bottom-left
one, and nothing converts between them yet (`spikot-win-80o.1`).

### Permissions

**Accessibility is required.** Window moves, raises and title reads all go through it.

TCC attributes a permission check to the **responsible process**, not to the binary that
runs. Measured on this machine: `spikot-wm` run from Ghostty reports
`AXIsProcessTrusted() == true` because it borrows Ghostty's grant, while the same bundle
launched with `open`, where it is its own responsible process, reports `false`. So no
spikot-wm binary has ever held a grant of its own; run from a keybinding it borrows skhd's.

`spikot-agent` is its own responsible process as a LaunchAgent, so it asks for
Accessibility itself on first launch and logs how to grant it.

`spikot-wm doctor` asks the running agent over the socket and reports its version, pid,
bundle identifier and its own Accessibility state. That last field has to come from the
agent: a local check answers for the calling process, which inherits the terminal's grant.
For the same reason `spikot-agent --check-permissions` cannot answer the question when run
from a shell, and it is not installed on `PATH`.

An agent that does not send `accessibility` and `bundleId` in its ping reply predates those
fields; doctor reports that rather than treating the absence as a negative answer, which it
did at first and which made a healthy older agent look broken.

`make bundle` ad-hoc signs with an explicit identifier-only designated requirement. Without
`-r`, an ad-hoc signature's requirement is `cdhash H"..."`, which pins the exact binary:
two builds differing by one string literal produce different cdhashes, so each rebuild
would be a new principal to TCC and the grant would need giving again. With `-r` the
requirement is just `identifier "org.traf.spikot-wm"` and is byte-identical across
rebuilds. A self-signed certificate would also work, but there are 0 codesigning
identities on this machine.

Confirmed end to end: after granting Accessibility to `SpikotWM.app` once, changing a
string literal in the agent and running `make bundle` produced a different cdhash
(`88c8740c…` to `8c812c2b…`) and the grant still reported granted. The check ran under
`launchctl submit`, so the agent was its own responsible process rather than borrowing the
terminal's grant; the control, a bundle-less `spikot-wm doctor` run the same way, reported
`accessibility [FAIL] this process is not trusted`. So rebuilds do not cost the grant.

**Screen Recording is not required.** It only affects `kCGWindowName`, and titles come
from `kAXTitle` instead, which needs only Accessibility. `ScreenRecording.request()` exists
but is deliberately never called.

### Hotkeys

`HotkeyController` (Sources/Agent/Hotkeys.swift) registers the config's `hotkeys` table with
Carbon `RegisterEventHotKey` and runs each binding through `AgentEngine.handle`, the same
entry point the socket uses. A binding is literally a `Request`, so hotkeys inherit the whole
command vocabulary; `IPC.commands` is the list they are validated against, and it has to
match the switch in `AgentEngine.handle`.

Parsing lives in `StateCore/hotkeys.swift` rather than the agent, so it is testable without a
run loop. `HotkeySpec.keyCodes` repeats Carbon's `kVK_*` values as plain numbers; the test
suite asserts every one against the real constant, which is the only thing standing between a
transposed digit and a binding that silently lands on a neighbouring key.

Carbon rather than the alternatives: it consumes the keystroke, needs no TCC permission, and
works over full-screen apps and Spaces. `NSEvent.addGlobalMonitorForEvents` cannot consume,
so `alt-h` would still type an `h`; `CGEventTap` can, but needs Input Monitoring and has to
re-arm after `kCGEventTapDisabledByTimeout`.

Two things measured while building it, both of which change what the code can promise:

- `eventHotKeyExistsErr` (-9878) means **this process** already registered that combination.
  With the agent holding ctrl-alt-shift-F19, a second process registering the same
  combination got `noErr`. So a clash with skhd or Rectangle cannot be detected at all: the
  key just never arrives. The error is reported as a duplicate inside our own table, found by
  comparing canonical forms before registering, so `cmd-shift-1` and `shift+cmd+1` are
  recognised as one key.
- A synthetic `CGEventPost`, even with the modifiers pressed as real key events first, does
  not drive hotkey dispatch. Verified against a minimal `InstallEventHandler` plus
  `RegisterEventHotKey` receiver, which also never fired, so it is the posting method rather
  than this code. Pressing the key is a manual test; see `manual-tests.org`.

`hotkeysEnabled` defaults to false. `AgentEngine.onConfigChange` re-syncs the registrations,
so the menu toggle and a `reload` both take effect without a restart.

### Package Structure

- `CSpikotAX`: C target whose only job is to declare the private
  `_AXUIElementGetWindow`, which has no public header. SwiftPM has no bridging header, so
  the declaration needs a target of its own
- `SpikotAX`: Accessibility layer. `WindowIdentity` maps between `AXUIElement` and
  `CGWindowID`, reads and writes window frames, and reads titles; `Accessibility` handles
  permission
- `StateCore`: State, Window types and helpers. Re-exports `SpikotAX`, so importing
  `StateCore` is enough
- `StateTool` (Sources/State): `spikot-wm`
- `PlacerTool` (Sources/Placer): `spikot-placer`
- `AgentTool` (Sources/Agent): `spikot-agent`, the resident agent, shipped as
  `SpikotWM.app`

Dependencies run `CSpikotAX` → `SpikotAX` → `StateCore` → both executables.

## Common Commands

### spikot-wm commands

```bash
# Dump current and cached state
.build/debug/spikot-wm state

# List all visible windows
.build/debug/spikot-wm list                # legacy: number, app, pid - the default
.build/debug/spikot-wm list -f tsv         # adds title and stack, with a header
.build/debug/spikot-wm list -f json

# Focus next/previous window in current stack
.build/debug/spikot-wm focus up
.build/debug/spikot-wm focus down

# Switch to different stack
.build/debug/spikot-wm focus left
.build/debug/spikot-wm focus right
.build/debug/spikot-wm focus 0  # Direct stack selection

# Show the effective configuration and where it came from
.build/debug/spikot-wm config

# Check permissions, configuration, displays and cache
.build/debug/spikot-wm doctor
.build/debug/spikot-wm doctor --request-permission  # also show the Accessibility dialog
```

`focus` and the stack commands exit non-zero with a message when the request cannot be
carried out (an index outside the current layout, an empty target stack, or a frontmost
window that is in no managed stack). `doctor` exits non-zero if any check fails.

`state`, `list` and `focus` go through the agent when it is running and run in this process
when it is not. Only `IPCError.noDaemon` triggers that fallback; any other socket problem is
reported rather than silently worked around. `--no-daemon` or `SPIKOT_NO_DAEMON=1` forces
the local path, and `--explain` writes which path served the command to stderr.

Measured on this machine: `list` takes a median 8.6 ms through the agent against 33.8 ms
in-process, and both produce byte-identical output. The fallback is what makes the agent
optional: every keybinding keeps working with it stopped, crashed, or not installed.

### spikot-placer commands

```bash
# Move frontmost window to stack N
.build/debug/spikot-placer 0
.build/debug/spikot-placer 1
.build/debug/spikot-placer 2
```

## Known Limitations

- Window placement is WIP; the original design relied on external tools like Rectangle or Raycast
- Keybindings must be configured externally via Raycast or similar tools
- External monitor support assumes horizontal positioning (left or right) with no coordinate overlaps
- `currentStack()` picks the first window belonging to the frontmost process, not the
  focused one, so it can name the wrong window when an application has several. It no
  longer crashes when the frontmost process owns no managed window; it returns nil.
  Fixing the multi-window case needs the Accessibility API (`spikot-win-6sd.4`)
- Stack rotation in the `down` direction was noted as suspect. `rotateStack` used to
  re-read the frontmost application seven times per call, which could return different
  stacks before and after the rotation; it reads once as of v0.4.2. Whether that was the
  whole cause is unconfirmed
- Unmanaged applications come from `Config.ignoredApps`, which defaults to `["borders"]`
  (JankyBorders, whose overlay is a real layer-0 window about 16 points outside the window
  it decorates)
- `kCGWindowName` is nil for other applications' windows without Screen Recording
  permission, which is the case here, so titles come from `kAXTitle` instead. That costs
  one Accessibility round-trip per window, so only `list -f tsv` and `-f json` pay it

## Development Notes

- Configuration lives in `~/.config/spikot-wm/config.json`, overridable per-run by
  `SPIKOT_GAP`, `SPIKOT_MODE`, `SPIKOT_CACHE_PATH`, `SPIKOT_USE_CACHE` and `SPIKOT_LOG`,
  with the file path itself overridable by `SPIKOT_CONFIG`. Defaults come from
  `Config.standard`; the default gap is 10, matching Rectangle Pro's `gapSize`
- The version is only in `Sources/StateCore/Version.swift`; `make version-check` asserts
  it matches the newest git tag
- Logging is off until an executable calls `bootstrapLogging()`, and goes to stderr
  because stdout carries the parsed output of `list`. Set `SPIKOT_LOG=debug` to see it
- `make test` needs a `-load-plugin-library` flag for swift-testing's macros on a Command
  Line Tools-only install; the Makefile adds it when the plugin is present
- Linter settings live in `.swiftlint.yml`; the `todo` rule is disabled because the outstanding TODOs are tracked in `suggestions.md`
- The project uses Swift structured concurrency patterns (no Foundation.Logger in some places, standard print elsewhere)
- Window matching uses a tolerance of ±2 pixels when comparing bounds (winman.swift:53-56)
- State caching is validated by comparing mode configurations between runs


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

**This repository explicitly opts in to team-maintainer for commits.** See the Git Policy
section of `AGENTS.md`, which is authoritative: commit atomically after each completed
changeset, per the `ship` skill. `git push` and `bd dolt push` still require an explicit
request.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Confirm nothing is left uncommitted**. Work should already be committed changeset by
   changeset, so this is a check, not a batch commit:
   ```bash
   git status            # expect a clean tree
   git log --oneline -5  # the changesets from this session

   # Only when the user asks for the push:
   git pull --rebase && bd dolt push && git push
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Commit atomically after each completed changeset (see the Git Policy in `AGENTS.md`).
  Do not push (`git push`, `bd dolt push`) without an explicit request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
