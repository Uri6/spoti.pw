#import "LiveBarLayout.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static BOOL usableRect(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width > 0 && rect.size.height > 0;
}

@implementation SGRLiveBarLayout {
    __weak UIView *_parent;
    __weak UIWindow *_window;
    CGRect _naturalBounds, _cardRect, _appliedBounds;
    CGPoint _naturalCenter, _appliedCenter;
    BOOL _valid;
}
- (instancetype)initWithSource:(UIView *)source cardRect:(CGRect)cardRect {
    if ((self = [super init])) {
        _source = source;
        _parent = source.superview;
        _window = source.window;
        _naturalBounds = source.bounds;
        _naturalCenter = source.center;
        _cardRect = cardRect;
        _valid = source && _parent && _window && usableRect(cardRect) &&
            usableRect(source.bounds) && CGRectContainsRect(source.bounds, cardRect) &&
            CGAffineTransformIsIdentity(source.transform);
    }
    return self;
}
- (BOOL)placeCardInRect:(CGRect)rect ofView:(UIView *)host {
    NSAssert(NSThread.isMainThread, @"live bar placement is main-thread only");
    UIView *source = self.source;
    if (self.applying || !_valid || !_window || !source || source.superview != _parent ||
        source.window != _window || host.window != _window || !usableRect(rect) ||
        !CGAffineTransformIsIdentity(source.transform)) return NO;
    // Change layout space, never the transform. Fixed-size controls must fit after relayout;
    // UIKit's inline accessory is shorter than the ordinary Spotify card.
    if (rect.size.height < 44 || rect.size.height > 64) return NO;
    for (UIView *ancestor = _parent; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01 || !ancestor.userInteractionEnabled ||
            !CGAffineTransformIsIdentity(ancestor.transform) || ancestor.layer.mask) return NO;
        if (ancestor.clipsToBounds && !CGRectContainsRect(ancestor.bounds, [ancestor convertRect:rect fromView:host])) return NO;
    }
    CGRect local = [_parent convertRect:rect fromView:host];
    CGFloat left = CGRectGetMinX(_cardRect) - CGRectGetMinX(_naturalBounds);
    CGFloat right = CGRectGetMaxX(_naturalBounds) - CGRectGetMaxX(_cardRect);
    CGFloat top = CGRectGetMinY(_cardRect) - CGRectGetMinY(_naturalBounds);
    CGFloat bottom = CGRectGetMaxY(_naturalBounds) - CGRectGetMaxY(_cardRect);
    CGRect bounds = _naturalBounds;
    bounds.size.width = local.size.width + left + right;
    bounds.size.height = local.size.height + top + bottom;
    CGPoint center = CGPointMake(local.origin.x - left + bounds.size.width / 2,
                                local.origin.y - top + bounds.size.height / 2);
    _applying = YES;
    source.bounds = _appliedBounds = bounds;
    source.center = _appliedCenter = center;
    _placed = YES;
    [source setNeedsLayout];
    [source layoutIfNeeded];
    _applying = NO;
    // A constraint owner may have reclaimed the root during layout. Do not fight it every frame.
    BOOL retained = CGRectEqualToRect(source.bounds, bounds) && CGPointEqualToPoint(source.center, center);
    NSMutableArray<UIView *> *pending = [source.subviews mutableCopy];
    while (pending.count && retained) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01) continue;
        if ([view isKindOfClass:UIControl.class] && view.userInteractionEnabled) {
            CGRect control = [source convertRect:view.bounds fromView:view];
            retained = usableRect(control) && CGRectContainsRect(source.bounds, control);
        } else {
            [pending addObjectsFromArray:view.subviews];
        }
    }
    if (!retained) [self restore];
    return retained;
}
- (void)restore {
    NSAssert(NSThread.isMainThread, @"live bar restoration is main-thread only");
    if (!self.placed || self.applying) return;
    UIView *source = self.source;
    _applying = YES;
    _placed = NO;
    // Never overwrite geometry that Spotify has already replaced or apply coordinates in a new
    // parent. Each property is restored only while its last write is still ours.
    if (source && source.superview == _parent) {
        if (CGRectEqualToRect(source.bounds, _appliedBounds)) source.bounds = _naturalBounds;
        if (CGPointEqualToPoint(source.center, _appliedCenter)) source.center = _naturalCenter;
        [source setNeedsLayout];
        [source layoutIfNeeded];
    }
    _applying = NO;
}
- (BOOL)ownsCurrentGeometry {
    return self.placed && self.source && self.source.superview == _parent &&
        CGRectEqualToRect(self.source.bounds, _appliedBounds) && CGPointEqualToPoint(self.source.center, _appliedCenter);
}
- (UIView *)hitTest:(CGPoint)point fromView:(UIView *)host event:(UIEvent *)event {
    UIView *source = self.source;
    if (!self.placed || !source || source.superview != _parent || source.window != host.window) return nil;
    for (UIView *v = source; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01 || !v.userInteractionEnabled) return nil;
    }
    return [source hitTest:[source convertPoint:point fromView:host] withEvent:event];
}
@end
