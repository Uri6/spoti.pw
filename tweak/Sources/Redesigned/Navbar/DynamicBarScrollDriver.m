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
    [self expand];
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
- (void)expand {
    if (@available(iOS 26.0, *)) self.tabController.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorNever;
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
    if (!self.permitted || !isfinite(delta) || bottom - top < 32) { [self expand]; return; }
    CGPoint velocity = [pan velocityInView:scroll];
    if (fabs(velocity.x) > fabs(velocity.y)) return;
    if (offset <= top + 1) { _travel = 0; [self expand]; return; }
    if (delta == 0) return; // No intent from rubber-banding beyond either edge.
    if ((_travel > 0 && delta < 0) || (_travel < 0 && delta > 0)) _travel = 0;
    _travel += delta;
    if (_travel < -8) [self expand];
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
