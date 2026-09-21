#import "LiveBarConstraints.h"
#import "Core/SGViewTree.h"
#import <objc/runtime.h>
#include <math.h>

static BOOL equality(NSLayoutConstraint *c) {
    return c.active && c.relation == NSLayoutRelationEqual && c.multiplier == 1 && c.priority == UILayoutPriorityRequired;
}
static NSLayoutConstraint *heightConstraint(UIView *view) {
    NSLayoutConstraint *result = nil;
    for (NSLayoutConstraint *c in view.constraints) {
        if (!c.active || c.firstItem != view || c.secondItem || c.firstAttribute != NSLayoutAttributeHeight) continue;
        if (result || !equality(c) || fabs(c.constant - 56) > 0.01) return nil;
        result = c;
    }
    return result;
}
static BOOL edgePin(NSLayoutConstraint *c, UIView *a, UIView *b) {
    if (!equality(c) || c.constant != 0 || c.firstAttribute != c.secondAttribute) return NO;
    return (c.firstItem == a && c.secondItem == b) || (c.firstItem == b && c.secondItem == a);
}

@implementation SGRLiveBarConstraints {
    __weak UIView *_source, *_parent, *_card, *_content, *_art;
    NSArray<NSLayoutConstraint *> *_released, *_placement, *_edited;
    NSArray<NSNumber *> *_original, *_written, *_positions;
    BOOL _active;
    CGFloat _parentHeight;
}
- (instancetype)initWithSource:(UIView *)source card:(UIView *)card {
    if (!(self = [super init])) return nil;
    UIView *parent = source.superview;
    if (!parent || source.translatesAutoresizingMaskIntoConstraints ||
        ![card.accessibilityIdentifier isEqualToString:@"SPTNowPlayingBar"] ||
        card.superview.superview != source || fabs(source.bounds.size.height - 56) > 0.5 ||
        fabs(card.bounds.size.height - 56) > 0.5 || fabs(parent.bounds.size.height - 56) > 0.5) return nil;
    NSLayoutConstraint *sourceHeight = heightConstraint(source), *cardHeight = heightConstraint(card);
    if (!sourceHeight || !cardHeight) return nil;
    for (NSLayoutConstraint *c in source.constraints) {
        if (c.active && c.firstItem == source && (!c.secondItem || c.secondItem == source) && c != sourceHeight) return nil;
    }
    NSMutableArray *pins = [NSMutableArray array];
    NSMutableSet *attributes = [NSMutableSet set];
    // Unknown external ownership is not safe to override. Only the four observed zero edge pins.
    for (UIView *owner = parent; owner; owner = owner.superview) {
        for (NSLayoutConstraint *c in owner.constraints) {
            if (!c.active || (c.firstItem != source && c.secondItem != source)) continue;
            if (owner != parent || !edgePin(c, source, parent) ||
                ![@[@(NSLayoutAttributeTop), @(NSLayoutAttributeBottom), @(NSLayoutAttributeLeading), @(NSLayoutAttributeTrailing)] containsObject:@(c.firstAttribute)] ||
                [attributes containsObject:@(c.firstAttribute)]) return nil;
            [pins addObject:c];
            [attributes addObject:@(c.firstAttribute)];
        }
    }
    if (pins.count != 4) return nil;
    __block UIView *content = nil, *image = nil;
    __block NSUInteger contentCount = 0, imageCount = 0;
    Class imageClass = objc_lookUpClass("_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__");
    SGForEachView(card, ^(UIView *v) {
        if ([v.accessibilityIdentifier isEqualToString:@"now-playing-bar-content"]) { content = v; contentCount++; }
        if (imageClass && [v isKindOfClass:imageClass]) { image = v; imageCount++; }
    });
    if (contentCount != 1 || imageCount != 1 || ![image isDescendantOfView:content]) return nil;
    NSLayoutConstraint *top = nil, *bottom = nil;
    UIView *art = nil;
    for (UIView *candidate = image; candidate && candidate != content; candidate = candidate.superview) {
        NSLayoutConstraint *t = nil, *b = nil;
        NSUInteger matches = 0;
        for (NSLayoutConstraint *c in content.constraints) {
            if (!equality(c) || c.constant != 8) continue;
            if (c.firstItem == candidate && c.secondItem == content && c.firstAttribute == NSLayoutAttributeTop && c.secondAttribute == NSLayoutAttributeTop) { t = c; matches++; }
            if (c.firstItem == content && c.secondItem == candidate && c.firstAttribute == NSLayoutAttributeBottom && c.secondAttribute == NSLayoutAttributeBottom) { b = c; matches++; }
        }
        if (t && b && matches == 2) {
            if (art || fabs(candidate.bounds.size.width - 40) > 0.5 || fabs(candidate.bounds.size.height - 40) > 0.5) return nil;
            art = candidate; top = t; bottom = b;
        }
    }
    if (!art) return nil;
    _parentHeight = parent.bounds.size.height;
    _source = source; _parent = parent; _card = card; _content = content; _art = art;
    [pins addObject:sourceHeight];
    _released = pins;
    _edited = @[cardHeight, top, bottom];
    _original = @[@(cardHeight.constant), @(top.constant), @(bottom.constant)];
    _placement = @[[source.leftAnchor constraintEqualToAnchor:parent.leftAnchor],
                   [source.topAnchor constraintEqualToAnchor:parent.topAnchor],
                   [source.widthAnchor constraintEqualToConstant:source.bounds.size.width],
                   [source.heightAnchor constraintEqualToConstant:source.bounds.size.height],
                   // The original root height plus edge pins also size the enclosing Spotify bar.
                   // Releasing those pins must not remove that sizing contribution or move the
                   // entire overlay/page inset while we convert accessory coordinates.
                   [parent.heightAnchor constraintEqualToConstant:_parentHeight]];
    return self;
}
- (BOOL)ownsConstraints {
    if (!_active || !_source || _source.superview != _parent || _card.superview.superview != _source ||
        ![_art isDescendantOfView:_content] || ![_content isDescendantOfView:_card]) return NO;
    for (NSLayoutConstraint *c in _released) if (c.active) return NO;
    for (NSUInteger i = 0; i < _placement.count; i++) {
        NSLayoutConstraint *c = _placement[i];
        if (!equality(c) || c.constant != _positions[i].doubleValue) return NO;
    }
    for (NSUInteger i = 0; i < _edited.count; i++) {
        NSLayoutConstraint *c = _edited[i];
        if (!equality(c) || c.constant != _written[i].doubleValue) return NO;
    }
    return YES;
}
- (BOOL)applyFrame:(CGRect)frame cardHeight:(CGFloat)height {
    if (!_source || _source.superview != _parent || (_active && !self.ownsConstraints)) return NO;
    if (!_active) {
        for (NSLayoutConstraint *c in _released) if (!c.active) return NO;
        for (NSUInteger i = 0; i < _edited.count; i++) if (!equality(_edited[i]) || _edited[i].constant != _original[i].doubleValue) return NO;
        [NSLayoutConstraint deactivateConstraints:_released];
        _active = YES;
    }
    // Keep the measured 40 pt artwork and control row at its natural size in a 48 pt accessory.
    _written = @[@(height), @((height - 40) / 2), @((height - 40) / 2)];
    for (NSUInteger i = 0; i < _edited.count; i++) _edited[i].constant = _written[i].doubleValue;
    _positions = @[@(frame.origin.x - _parent.bounds.origin.x), @(frame.origin.y - _parent.bounds.origin.y), @(frame.size.width), @(frame.size.height), @(_parentHeight)];
    for (NSUInteger i = 0; i < _placement.count; i++) _placement[i].constant = _positions[i].doubleValue;
    [NSLayoutConstraint activateConstraints:_placement];
    [_parent setNeedsLayout];
    [_parent layoutIfNeeded];
    return self.ownsConstraints;
}
- (void)restore {
    if (!_active) return;
    _active = NO;
    [NSLayoutConstraint deactivateConstraints:_placement];
    for (NSUInteger i = 0; i < _edited.count; i++) {
        NSLayoutConstraint *c = _edited[i];
        if (c.active && c.constant == _written[i].doubleValue) c.constant = _original[i].doubleValue;
    }
    // Cross-parent constraints must never be resurrected after Spotify replaces the view.
    if (_source && _source.superview == _parent) {
        [NSLayoutConstraint activateConstraints:_released];
        [_parent setNeedsLayout];
        [_parent layoutIfNeeded];
    }
}
@end
