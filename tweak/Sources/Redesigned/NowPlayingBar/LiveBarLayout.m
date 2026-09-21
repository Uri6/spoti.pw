#import "LiveBarLayout.h"
#import "LiveBarConstraints.h"
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
    __weak UIView *_cardView;
    CGRect _naturalBounds, _cardRect, _appliedBounds;
    CGPoint _naturalCenter, _appliedCenter;
    BOOL _valid;
    BOOL _tracksCard;
    SGRLiveBarConstraints *_constraints;
}
- (instancetype)initWithSource:(UIView *)source cardView:(UIView *)card {
    if ((self = [self initWithSource:source cardRect:[source convertRect:card.bounds fromView:card]])) {
        _tracksCard = YES;
        _cardView = card;
        _valid &= card && (card == source || [card isDescendantOfView:source]);
        if (!source.translatesAutoresizingMaskIntoConstraints) {
            _constraints = [[SGRLiveBarConstraints alloc] initWithSource:source card:card];
            _valid &= _constraints != nil;
        }
    }
    return self;
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
    _rejectionReason = nil;
    UIView *source = self.source;
    if (self.applying || !_valid || !_window || !source || source.superview != _parent ||
        source.window != _window || host.window != _window || !usableRect(rect) ||
        !CGAffineTransformIsIdentity(source.transform)) return [self reject:@"source ownership, window or geometry unavailable"];
    if (_tracksCard && (!_cardView || _cardView.window != _window || _cardView.hidden || _cardView.alpha < 0.01 ||
        (_cardView != source && ![_cardView isDescendantOfView:source]))) return [self reject:@"card detached or hidden"];
    // Change layout space, never the transform. Fixed-size controls must fit after relayout;
    // UIKit's inline accessory is shorter than the ordinary Spotify card.
    if (rect.size.height < 44 || rect.size.height > 64) return [self reject:@"accessory height outside supported range"];
    for (UIView *ancestor = _parent; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01 || !ancestor.userInteractionEnabled ||
            !CGAffineTransformIsIdentity(ancestor.transform) || ancestor.layer.mask) return [self reject:@"ancestor hidden, noninteractive, transformed or masked"];
        if (ancestor.clipsToBounds && !CGRectContainsRect(ancestor.bounds, [ancestor convertRect:rect fromView:host])) return [self reject:@"ancestor clips accessory placement"];
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
    _placed = YES;
    BOOL constraintPlacement = YES;
    if (_constraints) {
        CGRect frame = CGRectMake(center.x - bounds.size.width / 2, center.y - bounds.size.height / 2, bounds.size.width, bounds.size.height);
        constraintPlacement = [_constraints applyFrame:frame cardHeight:local.size.height];
    } else {
        source.bounds = bounds;
        source.center = center;
        [source setNeedsLayout];
        [source layoutIfNeeded];
    }
    _appliedBounds = bounds;
    _appliedCenter = center;
    _applying = NO;
    // A constraint owner may have reclaimed the root during layout. Do not fight it every frame.
    BOOL retained = constraintPlacement && fabs(source.bounds.size.width - bounds.size.width) <= 0.5 &&
        fabs(source.bounds.size.height - bounds.size.height) <= 0.5 &&
        fabs(source.center.x - center.x) <= 0.5 && fabs(source.center.y - center.y) <= 0.5;
    if (retained) { _appliedBounds = source.bounds; _appliedCenter = source.center; }
    if (!constraintPlacement) _rejectionReason = [NSString stringWithFormat:@"constraint lease: %@", _constraints.rejectionReason ?: @"unavailable"];
    else if (!retained) _rejectionReason = [NSString stringWithFormat:@"source geometry changed: bounds=%@ expected=%@ center=%@ expected=%@", NSStringFromCGRect(source.bounds), NSStringFromCGRect(bounds), NSStringFromCGPoint(source.center), NSStringFromCGPoint(center)];
    if (_tracksCard) {
        CGRect actual = [_cardView convertRect:_cardView.bounds toView:host];
        BOOL cardFits = fabs(actual.origin.x - rect.origin.x) <= 0.5 && fabs(actual.origin.y - rect.origin.y) <= 0.5 &&
            fabs(actual.size.width - rect.size.width) <= 0.5 && fabs(actual.size.height - rect.size.height) <= 0.5;
        if (!cardFits && retained) _rejectionReason = [NSString stringWithFormat:@"card did not relayout: actual %@, slot %@", NSStringFromCGRect(actual), NSStringFromCGRect(rect)];
        retained &= cardFits;
    }
    NSMutableArray<UIView *> *pending = [source.subviews mutableCopy];
    while (pending.count && retained) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01) continue;
        if ([view isKindOfClass:UIControl.class] && view.userInteractionEnabled) {
            CGRect control = [source convertRect:view.bounds fromView:view];
            retained = usableRect(control) && CGRectContainsRect(source.bounds, control);
            if (!retained) _rejectionReason = @"control outside resized source bounds";
        } else {
            [pending addObjectsFromArray:view.subviews];
        }
    }
    if (!retained) [self restore];
    return retained;
}
- (BOOL)reject:(NSString *)reason {
    _rejectionReason = reason;
    return NO;
}
- (void)restore {
    NSAssert(NSThread.isMainThread, @"live bar restoration is main-thread only");
    if (!self.placed || self.applying) return;
    UIView *source = self.source;
    _applying = YES;
    _placed = NO;
    // Never overwrite geometry that Spotify has already replaced or apply coordinates in a new
    // parent. Each property is restored only while its last write is still ours.
    if (_constraints) {
        [_constraints restore];
    } else if (source && source.superview == _parent) {
        if (CGRectEqualToRect(source.bounds, _appliedBounds)) source.bounds = _naturalBounds;
        if (CGPointEqualToPoint(source.center, _appliedCenter)) source.center = _naturalCenter;
        [source setNeedsLayout];
        [source layoutIfNeeded];
    }
    _applying = NO;
}
- (BOOL)ownsCurrentGeometry {
    return self.placed && (!_constraints || _constraints.ownsConstraints) && self.source && _window && self.source.window == _window &&
        self.source.superview == _parent && CGAffineTransformIsIdentity(self.source.transform) &&
        CGRectEqualToRect(self.source.bounds, _appliedBounds) && CGPointEqualToPoint(self.source.center, _appliedCenter);
}
- (UIView *)hitTest:(CGPoint)point fromView:(UIView *)host event:(UIEvent *)event {
    UIView *source = self.source;
    if (!self.ownsCurrentGeometry || source.window != host.window) return nil;
    for (UIView *v = source; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01 || !v.userInteractionEnabled) return nil;
    }
    return [source hitTest:[source convertPoint:point fromView:host] withEvent:event];
}
@end
