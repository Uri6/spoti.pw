#import "DynamicBarCoordinator.h"
#import "DynamicBarHost.h"
#import "DynamicBarCapabilities.h"
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Redesigned/NowPlayingBar/LiveBarLayout.h"

static char kSession;
static NSHashTable *sg_sessions;

static BOOL enabled(void) {
    static BOOL value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = SGRedesignedUI() && SGHidden(SGRKeyDynamicBar); });
    if (@available(iOS 26.0, *)) return value;
    return NO;
}

@interface SGRDynamicBarSession : NSObject <SGRDynamicBarHostDelegate>
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIViewController *tabs;
@property(nonatomic, weak) UIViewController *player;
@property(nonatomic, weak) UIViewController *fullPlayer;
@property(nonatomic, weak) UIView *stockBar;
@property(nonatomic, weak) UIView *card;
@property(nonatomic, weak) UITabBar *mirror;
@property(nonatomic, weak) UIVisualEffectView *glass;
@property(nonatomic, copy) NSArray<UIView *> *sources;
@property(nonatomic, copy) void (^select)(UIView *);
@property(nonatomic, strong) SGRDynamicBarHost *host;
@property(nonatomic, strong) SGRLiveBarLayout *layout;
@property(nonatomic, strong) NSHashTable *transitions;
@property(nonatomic) CGRect naturalCard;
@property(nonatomic) BOOL updating;
@property(nonatomic) BOOL keyboard;
@property(nonatomic) BOOL failedPlacement;
@property(nonatomic) CGFloat glassAlpha;
@property(nonatomic) CGFloat mirrorAlpha;
@property(nonatomic) BOOL mirrorInteraction;
@property(nonatomic) CGSize lastSize;
@property(nonatomic) uint32_t lastBlockers;
- (void)refresh;
- (void)detach;
@end

@implementation SGRDynamicBarSession
- (instancetype)init {
    if ((self = [super init])) {
        _transitions = [NSHashTable weakObjectsHashTable];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UIApplicationDidBecomeActiveNotification,
             UIAccessibilityVoiceOverStatusDidChangeNotification, UIContentSizeCategoryDidChangeNotification,
             UIAccessibilityReduceMotionStatusDidChangeNotification, UIAccessibilitySwitchControlStatusDidChangeNotification,
             UIAccessibilityAssistiveTouchStatusDidChangeNotification]) [center addObserver:self selector:@selector(changed:) name:name object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)changed:(NSNotification *)note {
    self.failedPlacement = NO;
    if ([note.name isEqualToString:UIApplicationWillResignActiveNotification]) [self detach];
    else [self refresh];
}
- (void)keyboardChanged:(NSNotification *)note {
    CGRect screen = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect rect = [self.window convertRect:screen fromWindow:nil];
    self.keyboard = CGRectGetHeight(CGRectIntersection(self.window.bounds, rect)) > 1;
    [self refresh];
}
- (void)detach {
    if (self.updating || (!self.host && !self.layout)) return;
    self.updating = YES;
    [self.layout restore];
    self.layout = nil;
    if (self.host) {
        [self.host invalidate];
        [self.host willMoveToParentViewController:nil];
        [self.host.view removeFromSuperview];
        [self.host removeFromParentViewController];
        self.host = nil;
        if (self.glass.alpha == 0) self.glass.alpha = self.glassAlpha;
        if (self.mirror.alpha == 0) self.mirror.alpha = self.mirrorAlpha;
        self.mirror.userInteractionEnabled = self.mirrorInteraction;
        if (!CGRectIsEmpty(self.naturalCard)) self.glass.frame = self.naturalCard;
    }
    self.updating = NO;
    [self.player.viewIfLoaded setNeedsLayout];
}
- (void)refresh {
    if (self.updating) return;
    if (!CGSizeEqualToSize(self.lastSize, self.window.bounds.size)) {
        self.lastSize = self.window.bounds.size;
        self.failedPlacement = NO;
        [self detach];
    }
    UIViewController *selected = nil;
    // Getter and return type verified in 9.1.78 class metadata (0x107d50c84).
    if ([self.tabs respondsToSelector:@selector(selectedViewController)]) selected = [(id)self.tabs selectedViewController];
    UIScrollView *scroll = SGRDynamicBarScrollOwner(selected);
    uint32_t blockers = 0;
    if (!self.window || self.stockBar.window != self.window || self.player.viewIfLoaded.window != self.window) blockers |= SGRDynamicBarDetached;
    if (!SGRDynamicBarViewVisible(self.stockBar) || !SGRDynamicBarViewVisible(self.player.viewIfLoaded) || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) blockers |= SGRDynamicBarStockHidden;
    if (self.window.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact) blockers |= SGRDynamicBarRegularWidth;
    if (self.keyboard) blockers |= SGRDynamicBarKeyboard;
    if (self.fullPlayer) blockers |= SGRDynamicBarFullPlayer;
    if (self.transitions.allObjects.count) blockers |= SGRDynamicBarTransition;
    if (UIAccessibilityIsVoiceOverRunning() || UIAccessibilityIsSwitchControlRunning() || UIAccessibilityIsAssistiveTouchRunning() ||
        UIAccessibilityIsReduceMotionEnabled() ||
        UIContentSizeCategoryIsAccessibilityCategory(self.window.traitCollection.preferredContentSizeCategory)) blockers |= SGRDynamicBarAccessibility;
    if (!scroll) blockers |= SGRDynamicBarNoScrollOwner;
    if (!self.card || !self.player) blockers |= SGRDynamicBarUnknownContent;
    else blockers |= SGRDynamicBarContentBlockers(self.player);
    NSUInteger index = self.mirror.selectedItem ? [self.mirror.items indexOfObject:self.mirror.selectedItem] : NSNotFound;
    if (index == NSNotFound || index >= self.sources.count || self.sources.count > 5) blockers |= SGRDynamicBarUnknownContent;
    CGRect natural = self.layout ? self.naturalCard : [self.player.view convertRect:self.card.bounds fromView:self.card];
    SGRDynamicBarContext context = {blockers, self.window.bounds.size.width - 112, 240, natural.size.height};
    blockers = SGRDynamicBarBlockers(context);
    if (self.lastBlockers != blockers) {
        self.lastBlockers = blockers;
        SGLog(@"dynamic bar: presentation blockers 0x%x", blockers);
    }
    if (blockers) { self.failedPlacement = NO; [self detach]; return; }
    if (self.failedPlacement) return;
    self.updating = YES;
    if (!self.host) {
        self.naturalCard = natural;
        self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.player.view cardRect:natural];
        self.host = [SGRDynamicBarHost new];
        self.host.delegate = self;
        self.glassAlpha = self.glass.alpha;
        self.mirrorAlpha = self.mirror.alpha;
        self.mirrorInteraction = self.mirror.userInteractionEnabled;
        [self.tabs addChildViewController:self.host];
        self.host.view.frame = self.tabs.view.bounds;
        self.host.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.host.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, -self.tabs.additionalSafeAreaInsets.bottom, 0);
        [self.tabs.view addSubview:self.host.view];
        [self.host didMoveToParentViewController:self.tabs];
    }
    self.host.observedScrollView = scroll;
    self.host.tabController.tabBar.tintColor = self.mirror.tintColor;
    [self.host setItems:self.mirror.items selectedIndex:index];
    self.host.permitsMinimization = YES;
    self.mirror.alpha = 0;
    self.mirror.userInteractionEnabled = NO;
    self.glass.alpha = 0;
    self.updating = NO;
    [self.host.view setNeedsLayout];
}
- (void)dynamicBarHost:(SGRDynamicBarHost *)host didSelectIndex:(NSUInteger)index {
    if (index >= self.sources.count) return;
    UIView *source = self.sources[index];
    self.failedPlacement = NO;
    [self detach];
    if (self.select) self.select(source);
}
- (void)dynamicBarHost:(SGRDynamicBarHost *)host accessoryRect:(CGRect)rect inView:(UIView *)view inline:(BOOL)inlineLayout {
    if (self.updating || host != self.host) return;
    SGRDynamicBarContext context = {SGRDynamicBarContentBlockers(self.player), rect.size.width, 240, rect.size.height};
    if (SGRDynamicBarBlockers(context) || ![self.layout placeCardInRect:rect ofView:view]) {
        SGLog(@"dynamic bar: live layout rejected; returning presentation to Spotify");
        [self detach];
        self.failedPlacement = YES;
    }
}
- (UIView *)dynamicBarHost:(SGRDynamicBarHost *)host hitTest:(CGPoint)point inView:(UIView *)view event:(UIEvent *)event {
    return host == self.host ? [self.layout hitTest:point fromView:view event:event] : nil;
}
- (BOOL)dynamicBarHost:(SGRDynamicBarHost *)host shouldHoldIndex:(NSUInteger)index {
    return host == self.host && index < self.sources.count && self.sources[index] == SGRowIn(self.stockBar).arrangedSubviews.firstObject;
}
- (void)dynamicBarHost:(SGRDynamicBarHost *)host didHoldIndex:(NSUInteger)index {
    if (![self dynamicBarHost:host shouldHoldIndex:index]) return;
    UIView *source = self.stockBar;
    [self detach];
    SGOpenModSettings(source);
}
@end

static SGRDynamicBarSession *session(UIWindow *window, BOOL create) {
    if (!enabled() || !window) return nil;
    SGRDynamicBarSession *value = objc_getAssociatedObject(window, &kSession);
    if (!value && create) {
        value = [SGRDynamicBarSession new];
        value.window = window;
        objc_setAssociatedObject(window, &kSession, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!sg_sessions) sg_sessions = [NSHashTable weakObjectsHashTable];
        [sg_sessions addObject:value];
    }
    return value;
}

void SGRDynamicBarUpdateTabs(UIViewController *container, UIView *stockBar, UITabBar *mirror,
                           NSArray<UIView *> *sources, void (^select)(UIView *source)) {
    SGRDynamicBarSession *value = session(stockBar.window, YES);
    if (!value || value.updating) return;
    if (value.tabs != container || value.stockBar != stockBar) [value detach];
    value.tabs = container; value.stockBar = stockBar; value.mirror = mirror;
    value.sources = sources; value.select = select;
    [value refresh];
}
void SGRDynamicBarUpdatePlayer(UIViewController *container, UIView *card, UIVisualEffectView *glass) {
    SGRDynamicBarSession *value = session(container.viewIfLoaded.window, YES);
    if (!value || value.updating || value.layout.applying) return;
    if (value.layout.placed && !value.layout.ownsCurrentGeometry) {
        [value detach];
        value.failedPlacement = YES; // Spotify reclaimed layout; do not compete on each pass.
    }
    if (value.player != container || value.card != card) { [value detach]; value.failedPlacement = NO; }
    value.player = container; value.card = card; value.glass = glass;
    [value refresh];
}
void SGRDynamicBarBeginTransition(UIView *bar, id transition) {
    SGRDynamicBarSession *value = session(bar.window, NO);
    if (!value || !transition) return;
    [value.transitions addObject:transition];
    [value detach];
}
void SGRDynamicBarEndTransition(id transition) {
    for (SGRDynamicBarSession *value in sg_sessions.allObjects) {
        if (![value.transitions containsObject:transition]) continue;
        [value.transitions removeObject:transition];
        [value refresh];
    }
}
void SGRDynamicBarPlayerVisibility(UIViewController *player, BOOL shown) {
    for (SGRDynamicBarSession *value in sg_sessions.allObjects) {
        if (shown ? player.viewIfLoaded.window != value.window : value.fullPlayer != player) continue;
        value.fullPlayer = shown ? player : nil;
        [value.transitions removeAllObjects]; // Called only by completed appearance callbacks.
        [value refresh];
    }
}
