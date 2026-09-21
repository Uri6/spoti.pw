#import <UIKit/UIKit.h>

// Keeps the native minimize policy stable for the lifetime of an eligible host. The real
// page remains the designated content scroll view; UIKit owns both transition directions.
// The existing pan recognizer is observed only for bounded diagnostic sampling.
@interface SGRDynamicBarScrollDriver : NSObject
@property(nonatomic, weak) UITabBarController *tabController;
@property(nonatomic, weak) UIScrollView *scrollView;
@property(nonatomic, getter=isPermitted) BOOL permitted;
// Connected only by the diagnostic build; observes geometry without driving layout.
@property(nonatomic, copy) void (^diagnosticEvent)(NSString *event);
- (void)invalidate;
@end
