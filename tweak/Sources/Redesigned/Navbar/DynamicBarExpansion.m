#import "DynamicBarExpansion.h"
#import <objc/runtime.h>

static void (*originalWithoutAnimation)(id, SEL, void (^)(void));
static __thread NSUInteger expansionDepth;
static NSUInteger wrapperCount;

// Preserve the animation context if UIKit wraps the minimize-policy reset in
// +performWithoutAnimation:, only while synchronously expanding our own native chrome. Every other
// invocation, including those on other threads, follows the original implementation unchanged.
static void withoutAnimation(id receiver, SEL selector, void (^actions)(void)) {
    if (expansionDepth && NSThread.isMainThread && actions) {
        wrapperCount++;
        actions();
    } else originalWithoutAnimation(receiver, selector, actions);
}
static void installCompatibility(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getClassMethod(UIView.class, @selector(performWithoutAnimation:));
        originalWithoutAnimation = (void *)method_setImplementation(method, (IMP)withoutAnimation);
    });
}
NSUInteger SGRDynamicBarExpansionWrapperCount(void) { return wrapperCount; }
BOOL SGRDynamicBarExpand(UITabBarController *controller, BOOL animated) {
    if (@available(iOS 26.0, *)) {
        if (!controller) return NO;
        if (controller.tabBarMinimizeBehavior == UITabBarMinimizeBehaviorNever) return YES;
        BOOL animate = animated && !UIAccessibilityIsReduceMotionEnabled() && controller.viewIfLoaded.window;
        if (animate) installCompatibility();
        [controller.view layoutIfNeeded];
        void (^changes)(void) = ^{
            if (animate) expansionDepth++;
            @try { controller.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorNever; }
            @finally { if (animate) expansionDepth--; }
            // Explicitly end the compatibility scope before asking Spotify's original player
            // hierarchy to finish its layout, so its own no-animation work stays unchanged.
            [controller.view layoutIfNeeded];
        };
        if (!animate) changes();
        else [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:changes completion:nil];
        return YES;
    }
    return NO;
}
