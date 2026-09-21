#import <UIKit/UIKit.h>

// The measured Spotify 9.1.78 audio layout only. A lease on its root placement, card height and
// artwork padding; all views, controller ownership and control sizes remain Spotify's.
@interface SGRLiveBarConstraints : NSObject
@property(nonatomic, readonly) BOOL ownsConstraints;
- (instancetype)initWithSource:(UIView *)source card:(UIView *)card;
- (BOOL)applyFrame:(CGRect)frame cardHeight:(CGFloat)height;
- (void)restore;
@end
