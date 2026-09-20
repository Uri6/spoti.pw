#include "DynamicBarPolicy.h"
#include <math.h>

uint32_t SGRDynamicBarBlockers(SGRDynamicBarContext context) {
    uint32_t reasons = context.blockers;
    // Never scale controls to make an unverified layout fit. The adapter supplies the measured
    // minimum; a conservative floor also prevents an empty/malformed measurement being accepted.
    if (!isfinite(context.availableWidth) || !isfinite(context.minimumContentWidth) ||
        !isfinite(context.contentHeight) || context.minimumContentWidth < 160 ||
        context.availableWidth < context.minimumContentWidth ||
        context.contentHeight < 44 || context.contentHeight > 64) {
        reasons |= SGRDynamicBarInvalidLayout;
    }
    return reasons;
}
