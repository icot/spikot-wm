// SPDX-FileCopyrightText: 2023-2026 Ignacio Coterillo
// SPDX-License-Identifier: Apache-2.0

// SwiftPM requires at least one compilable source in a C target. The declaration this
// target exists for lives in include/CSpikotAX.h; the symbol itself is resolved at link
// time against ApplicationServices, so there is nothing to define here.
#include "include/CSpikotAX.h"
