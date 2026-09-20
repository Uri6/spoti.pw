// Run without an iOS SDK:
// clang -std=c11 -Wall -Wextra -Werror -x c policy-test.c \
//   ../../tweak/Sources/Redesigned/Navbar/DynamicBarPolicy.m -lm -o /tmp/dynamic-bar-policy-test
#include "../../tweak/Sources/Redesigned/Navbar/DynamicBarPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    SGRDynamicBarContext audio = {0, 280, 240, 56};
    assert(SGRDynamicBarBlockers(audio) == 0);

    // A video/Jam/transition arriving while inline must revoke eligibility immediately, regardless
    // of whether the track URI and playing/paused values changed. There is no playback-state cache.
    const uint32_t interruptions[] = {
        SGRDynamicBarVideo, SGRDynamicBarExtraContent, SGRDynamicBarUnknownContent,
        SGRDynamicBarKeyboard, SGRDynamicBarFullPlayer, SGRDynamicBarTransition,
        SGRDynamicBarStockHidden, SGRDynamicBarDetached, SGRDynamicBarAccessibility,
        SGRDynamicBarRegularWidth, SGRDynamicBarNoScrollOwner, SGRDynamicBarDisabled,
    };
    for (unsigned i = 0; i < sizeof(interruptions) / sizeof(*interruptions); i++) {
        SGRDynamicBarContext changed = audio;
        changed.blockers = interruptions[i];
        assert(SGRDynamicBarBlockers(changed) & interruptions[i]);
        changed.blockers |= SGRDynamicBarTransition;
        assert(SGRDynamicBarBlockers(changed) & SGRDynamicBarTransition);
        changed.blockers &= ~SGRDynamicBarTransition;
        if (interruptions[i] != SGRDynamicBarTransition) assert(SGRDynamicBarBlockers(changed));
        changed.blockers = 0;
        assert(SGRDynamicBarBlockers(changed) == 0);
    }

    // Resizing never crosses into eligibility before the actual controls fit.
    for (int width = 0; width <= 1024; width++) {
        SGRDynamicBarContext resized = audio;
        resized.availableWidth = width;
        assert((SGRDynamicBarBlockers(resized) == 0) == (width >= 240));
    }
    const double invalid[] = {NAN, INFINITY, -INFINITY, -1, 0};
    for (unsigned i = 0; i < sizeof(invalid) / sizeof(*invalid); i++) {
        SGRDynamicBarContext malformed = audio;
        malformed.availableWidth = invalid[i];
        assert(SGRDynamicBarBlockers(malformed) & SGRDynamicBarInvalidLayout);
        malformed = audio;
        malformed.minimumContentWidth = invalid[i];
        assert(SGRDynamicBarBlockers(malformed) & SGRDynamicBarInvalidLayout);
        malformed = audio;
        malformed.contentHeight = invalid[i];
        assert(SGRDynamicBarBlockers(malformed) & SGRDynamicBarInvalidLayout);
    }
    audio.contentHeight = 80; // Extra rows do not get clipped to an ordinary audio card.
    assert(SGRDynamicBarBlockers(audio) & SGRDynamicBarInvalidLayout);
    puts("dynamic bar policy: interruption, fitting, and invalid geometry cases passed");
    return 0;
}
