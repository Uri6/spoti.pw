#import "ProbeExpansionMotion.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static CGFloat difference(CGRect a, CGRect b) {
    return MAX(MAX(fabs(a.origin.x - b.origin.x), fabs(a.origin.y - b.origin.y)),
               MAX(fabs(a.size.width - b.size.width), fabs(a.size.height - b.size.height)));
}
static CGRect presentationRect(UIView *view) {
    CALayer *layer = view.layer.presentationLayer;
    CALayer *window = view.window.layer.presentationLayer;
    if (!layer || !window) return CGRectNull;
    return [layer convertRect:layer.bounds toLayer:window];
}
@implementation ProbeExpansionMotion {
    __weak UIView *_player, *_accessory;
    __weak UILabel *_status;
    CADisplayLink *_link;
    BOOL _wasInline, _tracking, _published;
    NSUInteger _cycles, _movingFrames;
    CGRect _previous;
    CFTimeInterval _started;
}
- (instancetype)initWithPlayer:(UIView *)player accessory:(UIView *)accessory status:(UILabel *)status {
    if (!(self = [super init])) return nil;
    _player = player; _accessory = accessory; _status = status;
    status.accessibilityLabel = @"expansion-motion-0";
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(sample:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return self;
}
- (void)sample:(CADisplayLink *)link {
    if (!_player.window || !_accessory.window) return;
    BOOL inlineMode = [_status.accessibilityValue isEqualToString:@"inline"];
    if (_wasInline && !inlineMode) {
        _tracking = YES; _published = NO; _movingFrames = 0;
        _started = link.timestamp; _previous = CGRectNull;
    }
    _wasInline = inlineMode;
    if (!_tracking || inlineMode || link.timestamp - _started > 0.8) { _tracking = NO; return; }
    CGRect player = presentationRect(_player), accessory = presentationRect(_accessory);
    CGRect target = [_player convertRect:_player.bounds toView:_player.window];
    if (CGRectIsNull(player) || CGRectIsNull(accessory)) return;
    BOOL intermediate = difference(player, target) > 0.75;
    BOOL moving = !CGRectIsNull(_previous) && difference(player, _previous) > 0.15;
    BOOL aligned = difference(player, accessory) < 3;
    if (intermediate && moving && aligned) _movingFrames++;
    NSLog(@"PROBE expansion t=%.3f player=%@ accessory=%@ target=%@ moving=%d aligned=%d",
        link.timestamp - _started, NSStringFromCGRect(player), NSStringFromCGRect(accessory), NSStringFromCGRect(target), moving, aligned);
    _previous = player;
    if (_movingFrames >= 2 && !_published) {
        _published = YES;
        _status.accessibilityLabel = [NSString stringWithFormat:@"expansion-motion-%lu", (unsigned long)++_cycles];
    }
}
- (void)invalidate { [_link invalidate]; _link = nil; }
@end
