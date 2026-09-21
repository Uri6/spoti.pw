#import <UIKit/UIKit.h>

// Measured Spotify 9.1.78 audio/video layouts. Leases root placement, card height and media
// sizing while retaining original controller ownership, live surfaces and control sizes.
@interface SGRLiveBarConstraints : NSObject
@property(nonatomic, readonly) BOOL ownsConstraints;
- (instancetype)initWithSource:(UIView *)source card:(UIView *)card;
- (BOOL)applyFrame:(CGRect)frame cardHeight:(CGFloat)height;
- (void)restore;
@end
