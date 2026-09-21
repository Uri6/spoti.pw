#import <UIKit/UIKit.h>

// UIKit minimized for an external scroll owner on iOS 26.5, but did not expand on reversal. This
// adapter supplies that missing intent using the real page's existing pan recognizer. It never
// replaces the scroll delegate or synthesizes a scroll, touch, or private UIKit transition.
@interface SGRDynamicBarScrollDriver : NSObject
@property(nonatomic, weak) UITabBarController *tabController;
@property(nonatomic, weak) UIScrollView *scrollView;
@property(nonatomic, getter=isPermitted) BOOL permitted;
// Connected only by the diagnostic build; observes geometry without driving layout.
@property(nonatomic, copy) void (^diagnosticEvent)(NSString *event);
- (void)invalidate;
@end
