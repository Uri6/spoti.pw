// Presentation eligibility only. Spotify remains the owner of media and navigation state.
// No UIKit dependency: the same policy is exercised by the host-side regression tests.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef enum {
    SGRDynamicBarDisabled       = 1u << 0,
    SGRDynamicBarDetached       = 1u << 1,
    SGRDynamicBarStockHidden    = 1u << 2,
    SGRDynamicBarRegularWidth   = 1u << 3,
    SGRDynamicBarUnknownContent = 1u << 4,
    SGRDynamicBarVideo          = 1u << 5,
    SGRDynamicBarExtraContent   = 1u << 6,
    SGRDynamicBarAccessibility  = 1u << 7,
    SGRDynamicBarKeyboard       = 1u << 8,
    SGRDynamicBarFullPlayer     = 1u << 9,
    SGRDynamicBarTransition     = 1u << 10,
    SGRDynamicBarNoScrollOwner  = 1u << 11,
    SGRDynamicBarInvalidLayout  = 1u << 12,
} SGRDynamicBarBlocker;

typedef struct {
    uint32_t blockers;
    double availableWidth;
    double minimumContentWidth;
    double contentHeight;
} SGRDynamicBarContext;

// A zero result permits a native host. Every nonzero result requires handing presentation back to
// the existing bars, preserving Spotify's current visibility (not forcibly showing a hidden bar).
// Call again whenever content or geometry changes, including during an inline presentation.
uint32_t SGRDynamicBarBlockers(SGRDynamicBarContext context);
