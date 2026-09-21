#import <UIKit/UIKit.h>

// Test-only presentation-layer evidence. Endpoint traits alone cannot detect a jump cut.
@interface ProbeExpansionMotion : NSObject
- (instancetype)initWithPlayer:(UIView *)player accessory:(UIView *)accessory status:(UILabel *)status;
- (void)invalidate;
@end
