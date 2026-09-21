#import <UIKit/UIKit.h>

// Sanitized constraint topology captured on Spotify 9.1.78, without Spotify assets or binaries.
@interface FixtureAudioPlayer : NSObject
@property(nonatomic, readonly) UIView *source;
@property(nonatomic, readonly) UIView *card;
@property(nonatomic, readonly) UIView *artwork;
@property(nonatomic, readonly) UIView *videoSurface;
@property(nonatomic, readonly) NSLayoutConstraint *videoAspect;
@property(nonatomic, readonly) UILabel *status;
@property(nonatomic, readonly) UIButton *play;
@property(nonatomic, readonly) NSArray<NSLayoutConstraint *> *rootPins;
@property(nonatomic, readonly) NSLayoutConstraint *cardHeight;
@property(nonatomic, readonly) NSLayoutConstraint *artTop;
- (instancetype)initInParent:(UIView *)parent;
- (instancetype)initInParent:(UIView *)parent videoAspectRatio:(CGFloat)ratio;
@end
