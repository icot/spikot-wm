# spikot-wm

"Window Manager" for macOS. Intends to manage windows in tiled stacks.

## What works (at version 0.3.0):

- Works for a hardcoded mode (two* or three* columnar stacks)
- Supports one external monitor, plugged to the right of a laptop (guess my setup)
- Detect and manage properly new windows and window deletions

[*] If a external monitor is plugged, the mode name refers to the number of stacks in the main (external)
screen. The laptop display holds one additional stack

## Limitations

- Actual window placing is not implemented and depends on external tools like Rectangle or Raycast
- Keybinding functionality is implemented via wrapper scripts keybinded via Raycast

## Approach

- Single pass process of open, visible windows to match to stacks location
- Stack membership cached between executions

## Intentions

- Implement all functionality without 3rd party dependencies
