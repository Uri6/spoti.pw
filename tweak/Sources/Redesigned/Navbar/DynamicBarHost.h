#import <UIKit/UIKit.h>

@class SGRDynamicBarHost;
@protocol SGRDynamicBarHostDelegate <NSObject>
- (void)dynamicBarHost:(SGRDynamicBarHost *)host didSelectIndex:(NSUInteger)index;
- (void)dynamicBarHost:(SGRDynamicBarHost *)host accessoryRect:(CGRect)rect inView:(UIView *)view inline:(BOOL)inlineLayout;
- (UIView *)dynamicBarHost:(SGRDynamicBarHost *)host hitTest:(CGPoint)point inView:(UIView *)view event:(UIEvent *)event;
@end

// A contained UIKit chrome controller. Its children are presentation proxies; the real application
// page and live player retain their existing controller/view ownership. Only public UIKit APIs.
@interface SGRDynamicBarHost : UIViewController
@property(nonatomic, weak) id<SGRDynamicBarHostDelegate> delegate;
@property(nonatomic, weak) UIScrollView *observedScrollView;
@property(nonatomic) BOOL permitsMinimization;
@property(nonatomic, readonly) UITabBarController *tabController;
- (void)setItems:(NSArray<UITabBarItem *> *)items selectedIndex:(NSUInteger)index;
- (void)invalidate;
@end
