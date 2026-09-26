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
