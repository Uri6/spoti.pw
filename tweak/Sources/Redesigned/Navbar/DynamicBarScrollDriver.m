#import "DynamicBarScrollDriver.h"
#include <math.h>

@implementation SGRDynamicBarScrollDriver {
    CGFloat _lastOffset, _travel;
}
- (void)setScrollView:(UIScrollView *)scrollView {
    if (_scrollView == scrollView) return;
    [_scrollView.panGestureRecognizer removeTarget:self action:@selector(pan:)];
    _scrollView = scrollView;
    _travel = 0;
    [scrollView.panGestureRecognizer addTarget:self action:@selector(pan:)];
    [self expandAnimated:NO];
}
- (void)setPermitted:(BOOL)permitted {
    if (_permitted == permitted) return;
    _permitted = permitted;
    _travel = 0;
    if (@available(iOS 26.0, *)) {
        self.tabController.tabBarMinimizeBehavior = permitted ?
            UITabBarMinimizeBehaviorOnScrollDown : UITabBarMinimizeBehaviorNever;
    }
}
- (void)expandAnimated:(BOOL)animated {
    if (@available(iOS 26.0, *)) {
        UITabBarController *controller = self.tabController;
        if (!controller || controller.tabBarMinimizeBehavior == UITabBarMinimizeBehaviorNever) return;
        void (^changes)(void) = ^{
            controller.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorNever;
            // Keep native chrome and the original player's constraint lease in one transaction.
            [controller.view layoutIfNeeded];
        };
        if (!animated || UIAccessibilityIsReduceMotionEnabled() || !controller.viewIfLoaded.window) { changes(); return; }
        [controller.view layoutIfNeeded];
        [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes completion:nil];
    }
}
- (void)pan:(UIPanGestureRecognizer *)pan {
    UIScrollView *scroll = self.scrollView;
    if (!scroll || pan != scroll.panGestureRecognizer) return;
    CGFloat top = -scroll.adjustedContentInset.top;
    CGFloat bottom = MAX(top, scroll.contentSize.height - scroll.bounds.size.height + scroll.adjustedContentInset.bottom);
    CGFloat offset = MIN(bottom, MAX(top, scroll.contentOffset.y));
    if (pan.state == UIGestureRecognizerStateBegan) {
        _lastOffset = offset;
        _travel = 0;
        return;
    }
    if (pan.state != UIGestureRecognizerStateChanged) {
        _travel = 0;
        // UIKit starts observing minimization at the next gesture. Leaving `.never` in place
        // until that gesture is already moving loses its beginning and can miss the whole drag.
        if (self.permitted && (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled)) {
            if (@available(iOS 26.0, *)) self.tabController.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
        }
        return;
    }
    CGFloat delta = offset - _lastOffset;
    _lastOffset = offset;
    if (!self.permitted || !isfinite(delta) || bottom - top < 32) { [self expandAnimated:NO]; return; }
    CGPoint velocity = [pan velocityInView:scroll];
    if (fabs(velocity.x) > fabs(velocity.y)) return;
    if (offset <= top + 1) { _travel = 0; [self expandAnimated:YES]; return; }
    if (delta == 0) return; // No intent from rubber-banding beyond either edge.
    if ((_travel > 0 && delta < 0) || (_travel < 0 && delta > 0)) _travel = 0;
    _travel += delta;
    if (_travel < -8) [self expandAnimated:YES];
    else if (_travel > 24) {
        if (@available(iOS 26.0, *)) self.tabController.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
    }
}
- (void)invalidate {
    self.permitted = NO;
    self.scrollView = nil;
    self.tabController = nil;
}
- (void)dealloc {
    [_scrollView.panGestureRecognizer removeTarget:self action:@selector(pan:)];
}
@end
