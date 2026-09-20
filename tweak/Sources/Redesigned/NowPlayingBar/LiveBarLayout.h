#import <UIKit/UIKit.h>

// A reversible placement of an existing live mini-player. It never reparents a view or controller,
// changes constraints, scales controls, or copies a video surface. Call restore BEFORE Spotify's
// next layout/snapshot, then capture its new natural geometry if hosting is still eligible.
@interface SGRLiveBarLayout : NSObject
@property(nonatomic, readonly, getter=isApplying) BOOL applying;
@property(nonatomic, readonly, getter=isPlaced) BOOL placed;
@property(nonatomic, weak, readonly) UIView *source;
- (instancetype)initWithSource:(UIView *)source cardRect:(CGRect)cardRect;
- (BOOL)placeCardInRect:(CGRect)rect ofView:(UIView *)host;
- (void)restore;
// Allows a passthrough chrome host to deliver a touch to the original control and recognizers,
// including when the card is visually outside its original parent's hit-test rectangle.
- (UIView *)hitTest:(CGPoint)point fromView:(UIView *)host event:(UIEvent *)event;
@end
