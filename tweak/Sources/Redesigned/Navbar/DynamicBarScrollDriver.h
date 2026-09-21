#import <UIKit/UIKit.h>

// Expands the owned native bar on a reverse drag using the public policy setter, with a scoped
// compatibility fix for its no-animation transaction on iOS 27.
// The real scroll delegate, gestures and application containment remain unchanged.
@interface SGRDynamicBarScrollDriver : NSObject
@property(nonatomic, weak) UITabBarController *tabController;
@property(nonatomic, weak) UIScrollView *scrollView;
@property(nonatomic, getter=isPermitted) BOOL permitted;
// Connected only by the diagnostic build; observes geometry without driving layout.
@property(nonatomic, copy) void (^diagnosticEvent)(NSString *event);
- (void)invalidate;
@end
