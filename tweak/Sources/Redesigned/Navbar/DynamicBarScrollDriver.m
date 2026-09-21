#import "DynamicBarScrollDriver.h"
#import "DynamicBarExpansion.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@implementation SGRDynamicBarScrollDriver {
    CGFloat _lastOffset, _travel;
    CADisplayLink *_diagnosticLink;
    CFTimeInterval _diagnosticStart;
}
- (void)sampleExpansion:(CADisplayLink *)link {
    if (!self.diagnosticEvent || link.timestamp - _diagnosticStart > 0.8) {
        [_diagnosticLink invalidate]; _diagnosticLink = nil;
        return;
    }
    if (@available(iOS 26.0, *)) {
        UIView *bar = self.tabController.tabBar;
        UIView *slot = self.tabController.bottomAccessory.contentView;
        CALayer *window = bar.window.layer.presentationLayer;
        CALayer *barLayer = bar.layer.presentationLayer, *slotLayer = slot.layer.presentationLayer;
        CGRect barRect = window && barLayer ? [barLayer convertRect:barLayer.bounds toLayer:window] : CGRectNull;
        CGRect slotRect = window && slotLayer ? [slotLayer convertRect:slotLayer.bounds toLayer:window] : CGRectNull;
        self.diagnosticEvent([NSString stringWithFormat:@"expansion sample t=%.3f bar=%@ slot=%@", link.timestamp - _diagnosticStart, NSStringFromCGRect(barRect), NSStringFromCGRect(slotRect)]);
    }
}
- (void)setScrollView:(UIScrollView *)scrollView {
    if (_scrollView == scrollView) return;
    [_scrollView.panGestureRecognizer removeTarget:self action:@selector(pan:)];
    _scrollView = scrollView;
    _travel = 0;
    [scrollView.panGestureRecognizer addTarget:self action:@selector(pan:)];
}
- (void)setPermitted:(BOOL)permitted {
    if (@available(iOS 26.0, *)) {
        permitted = permitted && SGRDynamicBarCanExpand(self.tabController.tabBar);
        UITabBarMinimizeBehavior policy = permitted ? UITabBarMinimizeBehaviorOnScrollDown : UITabBarMinimizeBehaviorNever;
        if (_permitted == permitted && self.tabController.tabBarMinimizeBehavior == policy) return;
        _permitted = permitted;
        _travel = 0;
        self.tabController.tabBarMinimizeBehavior = policy;
    }
}
// Keep the scrolling policy intact. A short reverse drag needs an explicit native expansion;
// UIKit's automatic reversal otherwise waits until the page reaches its leading edge.
- (void)recordExpansionIntent {
    if (!self.diagnosticEvent || _diagnosticLink) return;
    self.diagnosticEvent(@"native expansion intent");
    _diagnosticStart = CACurrentMediaTime();
    _diagnosticLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(sampleExpansion:)];
    // A diagnostic observer must not reduce ProMotion's cadence while a transition runs.
    float maximum = self.tabController.view.window.screen.maximumFramesPerSecond;
    if (maximum > 0) _diagnosticLink.preferredFrameRateRange = CAFrameRateRangeMake(MIN(80, maximum), maximum, maximum);
    [_diagnosticLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
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
    if (pan.state != UIGestureRecognizerStateChanged) { _travel = 0; return; }
    CGFloat delta = offset - _lastOffset;
    _lastOffset = offset;
    if (!self.permitted || !isfinite(delta) || bottom - top < 32) return;
    CGPoint velocity = [pan velocityInView:scroll];
    if (fabs(velocity.x) > fabs(velocity.y)) return;
    if (offset <= top + 1) {
        _travel = 0;
        if (SGRDynamicBarIsMinimized(self.tabController.tabBar)) {
            [self recordExpansionIntent];
            SGRDynamicBarExpand(self.tabController, YES);
        }
        return;
    }
    if (delta == 0) return; // No intent from rubber-banding beyond either edge.
    if ((_travel > 0 && delta < 0) || (_travel < 0 && delta > 0)) _travel = 0;
    _travel += delta;
    if (_travel < -8 && SGRDynamicBarIsMinimized(self.tabController.tabBar)) {
        [self recordExpansionIntent];
        SGRDynamicBarExpand(self.tabController, YES);
    }
}
- (void)invalidate {
    [_diagnosticLink invalidate]; _diagnosticLink = nil;
    self.diagnosticEvent = nil;
    self.permitted = NO;
    self.scrollView = nil;
    self.tabController = nil;
}
- (void)dealloc {
    [_scrollView.panGestureRecognizer removeTarget:self action:@selector(pan:)];
}
@end
