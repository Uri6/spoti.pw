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
    __weak UIView *_source, *_parent, *_card, *_content, *_art, *_videoSurface, *_videoView;
    NSArray<NSLayoutConstraint *> *_released, *_placement, *_edited;
    NSArray<NSNumber *> *_original, *_written, *_positions;
    BOOL _active;
    CGFloat _parentHeight, _videoAspect;
    NSArray<NSNumber *> *_dimensions;
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
    __block UIView *content = nil, *image = nil, *surface = nil;
    __block NSUInteger contentCount = 0, imageCount = 0, surfaceCount = 0;
    Class imageClass = objc_lookUpClass("_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__");
    Class surfaceClass = objc_lookUpClass("SPTVideoSurfaceImpl");
    SGForEachView(card, ^(UIView *v) {
        if ([v.accessibilityIdentifier isEqualToString:@"now-playing-bar-content"]) { content = v; contentCount++; }
        if (imageClass && [v isKindOfClass:imageClass]) { image = v; imageCount++; }
        if (surfaceClass && [v isKindOfClass:surfaceClass] && !v.hidden && v.alpha > 0.01) { surface = v; surfaceCount++; }
    });
    if (contentCount != 1) return nil;
    BOOL video = surfaceCount == 1 && imageCount == 0 && [surface isDescendantOfView:content];
    if (!video && (imageCount != 1 || surfaceCount != 0 || ![image isDescendantOfView:content])) return nil;
    UIView *media = video ? surface : image;
    NSLayoutConstraint *top = nil, *bottom = nil;
    UIView *art = nil;
    for (UIView *candidate = media; candidate && candidate != content; candidate = candidate.superview) {
        NSLayoutConstraint *t = nil, *b = nil;
        NSUInteger matches = 0;
        for (NSLayoutConstraint *c in content.constraints) {
            if (!equality(c) || c.constant != (video ? 0 : 8)) continue;
            if (c.firstItem == candidate && c.secondItem == content && c.firstAttribute == NSLayoutAttributeTop && c.secondAttribute == NSLayoutAttributeTop) { t = c; matches++; }
            if (c.firstItem == content && c.secondItem == candidate && c.firstAttribute == NSLayoutAttributeBottom && c.secondAttribute == NSLayoutAttributeBottom) { b = c; matches++; }
        }
        if (t && b && matches == 2) {
            if (art) return nil;
            if (!video && (fabs(candidate.bounds.size.width - 40) > 0.5 || fabs(candidate.bounds.size.height - 40) > 0.5)) return nil;
            art = candidate; top = t; bottom = b;
        }
    }
    if (!art) return nil;
    NSMutableArray *edited = [NSMutableArray arrayWithObject:cardHeight];
    NSMutableArray *dimensions = [NSMutableArray arrayWithObject:@0]; // card height
    if (video) {
        // Captured layout: content > wrapper > media > BarVideoVC.view > SPTVideoSurfaceImpl.
        // Keep that live surface in place. Only fixed dimensions matching its natural measured
        // size are leased; aspect constraints remain unchanged, including their priorities.
        UIView *videoView = surface.superview;
        if (videoView.superview != art || fabs(art.bounds.size.height - 56) > 0.5 ||
            fabs(videoView.bounds.size.height - 56) > 0.5) return nil;
        _videoAspect = videoView.bounds.size.width / videoView.bounds.size.height;
        if (!isfinite(_videoAspect) || _videoAspect < 0.5 || _videoAspect > 2.4) return nil;
        BOOL sized = NO;
        for (NSLayoutConstraint *c in videoView.constraints) {
            if (!c.active || c.firstItem != videoView ||
                (c.firstAttribute != NSLayoutAttributeWidth && c.firstAttribute != NSLayoutAttributeHeight)) continue;
            if (!c.secondItem) {
                CGFloat natural = c.firstAttribute == NSLayoutAttributeWidth ? videoView.bounds.size.width : 56;
                if (!equality(c) || fabs(c.constant - natural) > 0.5) return nil;
                [edited addObject:c];
                [dimensions addObject:c.firstAttribute == NSLayoutAttributeWidth ? @2 : @0];
                sized = YES;
            } else if (c.secondItem == videoView && c.firstAttribute != c.secondAttribute &&
                       c.relation == NSLayoutRelationEqual && c.constant == 0) {
                CGFloat ratio = c.firstAttribute == NSLayoutAttributeWidth ? _videoAspect : 1 / _videoAspect;
                if (fabs(c.multiplier - ratio) > 0.01) return nil;
                sized = YES;
            }
        }
        if (!sized) return nil;
        _videoView = videoView;
        _videoSurface = surface;
    } else {
        [edited addObjectsFromArray:@[top, bottom]];
        [dimensions addObjectsFromArray:@[@1, @1]]; // artwork padding
    }
    _parentHeight = parent.bounds.size.height;
    _source = source; _parent = parent; _card = card; _content = content; _art = art;
    [pins addObject:sourceHeight];
    _released = pins;
    _edited = edited;
    _dimensions = dimensions;
    NSMutableArray *original = [NSMutableArray array];
    for (NSLayoutConstraint *c in edited) [original addObject:@(c.constant)];
    _original = original;
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
    if (_videoAspect) {
        if (!_videoSurface || !_videoView || _videoSurface.superview != _videoView || _videoView.superview != _art) return NO;
        CGFloat height = _videoSurface.bounds.size.height;
        if (height <= 0 || fabs(height - _card.bounds.size.height) > 0.5 ||
            fabs(_videoSurface.bounds.size.width / height - _videoAspect) > 0.01) return NO;
    }
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
    // Audio keeps its 40 pt artwork. Video keeps its original aspect inside the 48 pt accessory.
    NSMutableArray *written = [NSMutableArray array];
    for (NSNumber *dimension in _dimensions) {
        CGFloat constant = dimension.integerValue == 1 ? (height - 40) / 2 : dimension.integerValue == 2 ? height * _videoAspect : height;
        [written addObject:@(constant)];
    }
    _written = written;
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
