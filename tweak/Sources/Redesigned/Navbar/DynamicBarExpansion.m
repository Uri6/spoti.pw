#import "DynamicBarExpansion.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

// Verified in UIKit's runtime metadata: _isMinimized B16@0:8 and _setMinimized: v20@0:8B16.
// Check the actual receiver on each runtime before calling; never resolve an ivar, walk private
// subviews, send a fake tap, or change Spotify's own tab bar. The public minimize-policy setter
// resets layout without animation on iOS 27 and therefore cannot serve as an expansion command.
static BOOL signature(id object, SEL selector, const char *result, NSUInteger arguments) {
    if (![object respondsToSelector:selector]) return NO;
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return NO;
    char type[16];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, result)) return NO;
    if (arguments == 3) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (strcmp(type, @encode(BOOL))) return NO;
    }
    return YES;
}
BOOL SGRDynamicBarCanExpand(UITabBar *bar) {
    return [bar isKindOfClass:UITabBar.class] &&
        signature(bar, NSSelectorFromString(@"_isMinimized"), @encode(BOOL), 2) &&
        signature(bar, NSSelectorFromString(@"_setMinimized:"), @encode(void), 3);
}
BOOL SGRDynamicBarIsMinimized(UITabBar *bar) {
    return SGRDynamicBarCanExpand(bar) && ((BOOL (*)(id, SEL))objc_msgSend)(bar, NSSelectorFromString(@"_isMinimized"));
}
BOOL SGRDynamicBarExpand(UITabBarController *controller, BOOL animated) {
    UITabBar *bar = controller.tabBar;
    if (!SGRDynamicBarCanExpand(bar)) return NO;
    if (!SGRDynamicBarIsMinimized(bar)) return YES;
    [controller.view layoutIfNeeded];
    void (^changes)(void) = ^{
        ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, NSSelectorFromString(@"_setMinimized:"), NO);
        [controller.view layoutIfNeeded];
    };
    if (!animated || UIAccessibilityIsReduceMotionEnabled() || !bar.window) changes();
    else [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes completion:nil];
    return YES;
}
