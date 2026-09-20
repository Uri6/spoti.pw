#import "DynamicBarHost.h"
#import "DynamicBarScrollDriver.h"

@interface SGRAccessorySlot : UIView
@property(nonatomic, weak) SGRDynamicBarHost *owner;
@end

@interface SGRChromePassthrough : UIView
@property(nonatomic, weak) SGRDynamicBarHost *owner;
@end

@interface SGRDynamicBarHost () <UITabBarControllerDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) UITabBarController *tabController;
@property(nonatomic, strong) SGRAccessorySlot *slot;
@property(nonatomic, strong) SGRDynamicBarScrollDriver *scrollDriver;
@property(nonatomic) BOOL holding;
@property(nonatomic, weak) UILongPressGestureRecognizer *hold;
@end

@implementation SGRAccessorySlot
- (instancetype)init {
    if ((self = [super init])) {
        if (@available(iOS 26.0, *)) {
            [self registerForTraitChanges:@[UITraitTabAccessoryEnvironment.class]
                             withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
                [(UIView *)environment setNeedsLayout];
            }];
        }
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 48); }
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.window) return;
    if (@available(iOS 26.0, *)) {
        [self.owner.delegate dynamicBarHost:self.owner accessoryRect:self.bounds inView:self
                                    inline:self.traitCollection.tabAccessoryEnvironment == UITabAccessoryEnvironmentInline];
    }
}
@end

@implementation SGRChromePassthrough
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    UIView *playerHit = [self.owner.delegate dynamicBarHost:self.owner hitTest:point inView:self event:event];
    if (playerHit) return playerHit;
    UIView *hit = [super hitTest:point withEvent:event];
    UITabBar *bar = self.owner.tabController.tabBar;
    // The source player's own hierarchy supplies all player targets. Empty accessory space and
    // empty proxy content must not consume a browsing-page gesture.
    return hit == bar || [hit isDescendantOfView:bar] ? hit : nil;
}
@end

@implementation SGRDynamicBarHost
- (void)loadView {
    SGRChromePassthrough *view = [SGRChromePassthrough new];
    view.owner = self;
    view.backgroundColor = UIColor.clearColor;
    view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view = view;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 26.0, *)) {
        self.tabController = [UITabBarController new];
        self.tabController.delegate = self;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
        hold.delegate = self;
        [self.tabController.tabBar addGestureRecognizer:hold];
        self.hold = hold;
        self.scrollDriver = [SGRDynamicBarScrollDriver new];
        self.scrollDriver.tabController = self.tabController;
        self.scrollDriver.scrollView = self.observedScrollView;
        self.scrollDriver.permitted = self.permitsMinimization;
        self.tabController.tabBarMinimizeBehavior = self.permitsMinimization ?
            UITabBarMinimizeBehaviorOnScrollDown : UITabBarMinimizeBehaviorNever;
        self.slot = [SGRAccessorySlot new];
        self.slot.owner = self;
        self.slot.accessibilityElementsHidden = YES;
        self.tabController.bottomAccessory = [[UITabAccessory alloc] initWithContentView:self.slot];
        [self addChildViewController:self.tabController];
        self.tabController.view.frame = self.view.bounds;
        self.tabController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.tabController.view.backgroundColor = UIColor.clearColor;
        [self.view addSubview:self.tabController.view];
        [self.tabController didMoveToParentViewController:self];
    }
}
- (void)setItems:(NSArray<UITabBarItem *> *)items selectedIndex:(NSUInteger)index {
    [self loadViewIfNeeded];
    if (items.count == 0 || index >= items.count) return;
    if (self.tabController.viewControllers.count != items.count) {
        NSMutableArray<UIViewController *> *pages = [NSMutableArray array];
        for (NSUInteger i = 0; i < items.count; i++) {
            UIViewController *proxy = [UIViewController new];
            proxy.view.backgroundColor = UIColor.clearColor;
            [proxy setContentScrollView:self.observedScrollView forEdge:NSDirectionalRectEdgeAll];
            [pages addObject:proxy];
        }
        self.tabController.viewControllers = pages;
        self.tabController.customizableViewControllers = @[];
    }
    [items enumerateObjectsUsingBlock:^(UITabBarItem *item, NSUInteger i, BOOL *stop) {
        UIViewController *proxy = self.tabController.viewControllers[i];
        UITabBarItem *mirror = proxy.tabBarItem;
        if (![mirror.title isEqualToString:item.title]) mirror.title = item.title;
        if (mirror.image != item.image) mirror.image = item.image;
        if (mirror.selectedImage != item.selectedImage) mirror.selectedImage = item.selectedImage;
        mirror.accessibilityLabel = item.accessibilityLabel ?: item.title;
        mirror.tag = i;
    }];
    if (self.tabController.selectedIndex != index) self.tabController.selectedIndex = index;
}
- (BOOL)tabBarController:(UITabBarController *)controller shouldSelectViewController:(UIViewController *)viewController {
    if (self.holding) return NO;
    NSUInteger index = [controller.viewControllers indexOfObject:viewController];
    if (index != NSNotFound) [self.delegate dynamicBarHost:self didSelectIndex:index];
    // Selection follows the actual application after it accepts the original action.
    return NO;
}
- (void)setObservedScrollView:(UIScrollView *)scrollView {
    if (_observedScrollView == scrollView) return;
    _observedScrollView = scrollView;
    self.scrollDriver.scrollView = scrollView;
    for (UIViewController *proxy in self.tabController.viewControllers) {
        [proxy setContentScrollView:scrollView forEdge:NSDirectionalRectEdgeAll];
    }
}
- (NSUInteger)itemIndexAt:(CGPoint)point {
    UITabBar *bar = self.tabController.tabBar;
    NSUInteger index = NSNotFound;
    CGFloat distance = CGFLOAT_MAX;
    NSMutableArray<UIView *> *pending = [bar.subviews mutableCopy];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01 || CGRectIsEmpty(view.bounds)) continue;
        [pending addObjectsFromArray:view.subviews];
        CGFloat dx = fabs([view convertPoint:CGPointMake(CGRectGetMidX(view.bounds), 0) toView:bar].x - point.x);
        for (NSUInteger i = 0; i < bar.items.count && dx < distance; i++) {
            UITabBarItem *item = bar.items[i];
            BOOL match = [view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:item.title];
            if ([view isKindOfClass:UIImageView.class]) {
                UIImage *image = ((UIImageView *)view).image;
                match |= image && (image == item.image || image == item.selectedImage);
            }
            if (match) { index = i; distance = dx; }
        }
    }
    return index;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture != self.hold) return YES;
    NSUInteger index = [self itemIndexAt:[gesture locationInView:self.tabController.tabBar]];
    return index != NSNotFound && [self.delegate respondsToSelector:@selector(dynamicBarHost:shouldHoldIndex:)] &&
        [self.delegate dynamicBarHost:self shouldHoldIndex:index];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (void)held:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        NSUInteger index = [self itemIndexAt:[gesture locationInView:self.tabController.tabBar]];
        if (index != NSNotFound && [self.delegate respondsToSelector:@selector(dynamicBarHost:didHoldIndex:)]) [self.delegate dynamicBarHost:self didHoldIndex:index];
    } else if (gesture.state != UIGestureRecognizerStateChanged) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ weakSelf.holding = NO; });
    }
}
- (void)setPermitsMinimization:(BOOL)permitsMinimization {
    _permitsMinimization = permitsMinimization;
    self.scrollDriver.permitted = permitsMinimization;
}
- (void)invalidate {
    [self.scrollDriver invalidate];
    self.permitsMinimization = NO;
    self.observedScrollView = nil;
    self.delegate = nil;
    self.slot.owner = nil;
    self.tabController.delegate = nil;
}
@end
