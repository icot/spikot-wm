#ifndef CSPIKOT_AX_H
#define CSPIKOT_AX_H

#include <ApplicationServices/ApplicationServices.h>

/// Writes the CGWindowID of an accessibility window element into `identifier`.
///
/// PRIVATE, UNDOCUMENTED SYMBOL. It is exported by ApplicationServices but declared in no
/// public header, which is why this shim exists: SwiftPM has no bridging header, so the
/// declaration needs a C target of its own.
///
/// Why use it at all: correlating an AXUIElement to a CGWindowID has no public API. The
/// alternative, and what this project did before, is comparing the element's position and
/// size against CGWindowList bounds with a tolerance. That cannot tell apart two windows
/// of the same application with near-identical frames, and it silently matches nothing
/// when macOS has moved the window between the two reads.
///
/// Stability: present for over a decade, and used by Rectangle
/// (Rectangle/Rectangle-Bridging-Header.h:7, called at
/// Rectangle/Utilities/AXExtension.swift:88), yabai and Amethyst. Apple can still remove
/// it. Every call goes through one Swift function that falls back to the geometry match,
/// so if the symbol disappears only that function changes. StateCoreTests has a test that
/// calls it, which fails loudly on a macOS that drops it rather than silently degrading.
///
/// Returns kAXErrorSuccess and sets `identifier` on success; leaves `identifier`
/// untouched and returns a non-success AXError otherwise, including for an element that
/// is not a window.
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

#endif /* CSPIKOT_AX_H */
