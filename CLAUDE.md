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

# Install to /tmp/bin (default prefix)
make install

# Install to custom location
make install prefix=/usr/local

# Lint code
make lint

# Clean build artifacts
rm -rf .build
```

The project requires Swift 5.7.3+ and macOS 13+.

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
4. Iterates through the app's windows to find matching bounds
5. Sets new position and size via `AXUIElementSetAttributeValue()`

**Important**: The app must have Accessibility permissions granted in System Settings.

### Package Structure

- `StateCore`: Shared library containing all core logic (State, Window types, helpers)
- `StateTool` (Sources/State): Executable that manages state and focus/rotation commands
- `PlacerTool` (Sources/Placer): Executable that places windows using Accessibility API

Both executables depend on `StateCore`, enabling code reuse while maintaining separation of concerns.

## Common Commands

### spikot-wm commands

```bash
# Dump current and cached state
.build/debug/spikot-wm state

# List all visible windows
.build/debug/spikot-wm list

# Focus next/previous window in current stack
.build/debug/spikot-wm focus up
.build/debug/spikot-wm focus down

# Switch to different stack
.build/debug/spikot-wm focus left
.build/debug/spikot-wm focus right
.build/debug/spikot-wm focus 0  # Direct stack selection
```

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
- The `currentStack()` method can fail if multiple windows per process exist (see bug note at state.swift:162)
- Stack rotation down direction may be buggy due to state merging issues (see state.swift:279)
- The system filters out "borders" application windows (visual borders indicator app)

## Development Notes

- Configuration is currently hardcoded in main.swift files (gap: 5, activeMode: "twoColumns", cachePath)
- The project uses Swift structured concurrency patterns (no Foundation.Logger in some places, standard print elsewhere)
- Window matching uses a tolerance of ±2 pixels when comparing bounds (winman.swift:48-50)
- State caching is validated by comparing mode configurations between runs
