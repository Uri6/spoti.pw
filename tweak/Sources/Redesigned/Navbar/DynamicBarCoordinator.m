#import "DynamicBarCoordinator.h"
#import "DynamicBarHost.h"
#import "DynamicBarCapabilities.h"
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Redesigned/NowPlayingBar/LiveBarLayout.h"

static char kSession;
static NSHashTable *sg_sessions;
static void appendDiagnosticState(NSMutableString *out, BOOL launchEnabled);

static BOOL enabled(void) {
    static BOOL value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        value = SGRedesignedUI() && SGHidden(SGRKeyDynamicBar);
        SGLog(@"dynamic bar: %@ (launch setting)", value ? @"enabled" : @"disabled");
        [NSNotificationCenter.defaultCenter addObserverForName:SGDiagnosticSnapshotNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (NSThread.isMainThread && [note.object isKindOfClass:NSMutableString.class]) appendDiagnosticState(note.object, value);
        }];
    });
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
@property(nonatomic, strong) NSHashTable *mediaChanges;
@property(nonatomic) CGRect naturalCard;
@property(nonatomic) BOOL updating;
@property(nonatomic) BOOL refreshQueued;
@property(nonatomic) BOOL keyboard;
@property(nonatomic) BOOL failedPlacement;
@property(nonatomic) CGFloat glassAlpha;
@property(nonatomic) CGFloat mirrorAlpha;
@property(nonatomic) BOOL mirrorInteraction;
@property(nonatomic) CGSize lastSize;
@property(nonatomic) uint32_t lastBlockers;
@property(nonatomic, copy) NSString *lastRejection;
- (void)refresh;
- (void)detach;
@end

@implementation SGRDynamicBarSession
- (instancetype)init {
    if ((self = [super init])) {
        _transitions = [NSHashTable weakObjectsHashTable];
        _mediaChanges = [NSHashTable weakObjectsHashTable];
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
        // The player's styling hook owns the glass frame and runs during layout restoration.
        // It may already reflect new content; a cached frame must not overwrite that result.
    }
    self.updating = NO;
    [self.player.viewIfLoaded setNeedsLayout];
}
- (void)refresh {
    if (self.updating || self.layout.applying) return;
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
    if (self.transitions.allObjects.count || self.mediaChanges.allObjects.count) blockers |= SGRDynamicBarTransition;
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
        self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.player.view cardView:self.card];
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
    if (self.updating || self.layout.applying || host != self.host) return;
    SGRDynamicBarContext context = {SGRDynamicBarContentBlockers(self.player), rect.size.width, 240, rect.size.height};
    uint32_t blockers = SGRDynamicBarBlockers(context);
    if (blockers || ![self.layout placeCardInRect:rect ofView:view]) {
        self.lastRejection = blockers ? [NSString stringWithFormat:@"accessory blockers 0x%x", blockers] : (self.layout.rejectionReason ?: @"layout unavailable");
        SGLog(@"dynamic bar: live layout rejected (blockers 0x%x, %@); returning presentation to Spotify", blockers,
              blockers ? @"accessory eligibility" : (self.layout.rejectionReason ?: @"layout unavailable"));
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
    if (!value || value.updating || value.layout.applying) return;
    if (value.tabs != container || value.stockBar != stockBar || value.mirror != mirror) [value detach];
    value.tabs = container; value.stockBar = stockBar; value.mirror = mirror;
    value.sources = sources; value.select = select;
    [value refresh];
}
void SGRDynamicBarUpdatePlayer(UIViewController *container, UIView *card, UIVisualEffectView *glass) {
    SGRDynamicBarSession *value = session(container.viewIfLoaded.window, YES);
    if (!value || value.updating || value.layout.applying) return;
    if (value.layout.placed && !value.layout.ownsCurrentGeometry) {
        value.lastRejection = @"Spotify replaced source geometry between layouts";
        [value detach];
        value.failedPlacement = YES; // Spotify reclaimed layout; do not compete on each pass.
    }
    if (value.player != container || value.card != card || value.glass != glass) { [value detach]; value.failedPlacement = NO; }
    value.player = container; value.card = card; value.glass = glass;
    [value refresh];
}
// Async feed population does not necessarily relayout either bar. Coalesce relevant content-size
// and attachment events; never observe contentOffset, replace a delegate, poll, or scan each frame.
void SGRDynamicBarScrollChanged(UIScrollView *scroll) {
    if (!NSThread.isMainThread || !enabled()) return;
    for (SGRDynamicBarSession *value in sg_sessions.allObjects) {
        if (value.updating || value.layout.applying || value.refreshQueued) continue;
        UIViewController *selected = [value.tabs respondsToSelector:@selector(selectedViewController)] ? [(id)value.tabs selectedViewController] : nil;
        if ([selected isKindOfClass:UINavigationController.class]) selected = ((UINavigationController *)selected).visibleViewController;
        UIView *page = selected.viewIfLoaded;
        BOOL ownerChanged = value.host && scroll == value.host.observedScrollView;
        BOOL candidate = page && scroll.window == value.window && (scroll == page || [scroll isDescendantOfView:page]) &&
            scroll.bounds.size.width >= page.bounds.size.width * 0.65 && scroll.bounds.size.height >= page.bounds.size.height * 0.45;
        if (!ownerChanged && !candidate) continue;
        value.refreshQueued = YES;
        __weak SGRDynamicBarSession *weakValue = value;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRDynamicBarSession *live = weakValue;
            live.refreshQueued = NO;
            [live refresh];
        });
    }
}

id SGRDynamicBarBeginMediaChange(UIViewController *controller) {
    if (!NSThread.isMainThread || !enabled()) return nil;
    SGRDynamicBarSession *value = session(controller.viewIfLoaded.window, NO);
    if (!value || value.updating || value.layout.applying || !value.player) return nil;
    BOOL owned = NO;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController)
        if (parent == value.player) { owned = YES; break; }
    if (!owned) return nil;
    NSObject *token = [NSObject new];
    [value.mediaChanges addObject:token];
    [value detach];
    value.failedPlacement = NO;
    return token;
}
void SGRDynamicBarEndMediaChange(id token) {
    if (!token || !NSThread.isMainThread) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SGRDynamicBarSession *value in sg_sessions.allObjects) {
            if (![value.mediaChanges containsObject:token]) continue;
            // Other hooks can run during this pass; suspension remains until natural video
            // dimensions have settled. A fresh lease must never measure the old 48 pt card.
            [value.player.viewIfLoaded.superview layoutIfNeeded];
            [value.mediaChanges removeObject:token];
            value.failedPlacement = NO;
            [value refresh];
        }
    });
}

void SGRDynamicBarBeginTransition(UIView *bar, id transition) {
    if (!transition) return;
    // Some animators do not populate their bar ivar until setup. Suspend existing hosts before
    // that setup too; guessing an origin would capture the inline card in an expanded snapshot.
    NSArray *values = bar.window ? @[(session(bar.window, NO) ?: NSNull.null)] : sg_sessions.allObjects;
    for (id candidate in values) {
        if (![candidate isKindOfClass:SGRDynamicBarSession.class]) continue;
        SGRDynamicBarSession *value = candidate;
        [value.transitions addObject:transition];
        [value detach];
    }
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

// Keep the last rejection readable through the existing USB tree endpoint even when iOS drops a
// syslog message or the process changes during installation. These helpers only inspect UIKit.
static NSString *diagnosticItem(id item) {
    return item ? [NSString stringWithFormat:@"%@:%p", NSStringFromClass([item class]), item] : @"nil";
}

static void appendDiagnosticView(NSMutableString *out, NSString *role, UIView *view) {
    [out appendFormat:@"%@ %@ frame=%@ bounds=%@ visible=%d hidden=%d alpha=%.2f interactive=%d clips=%d autoresizing=%d\n",
        role, diagnosticItem(view), NSStringFromCGRect(view.frame), NSStringFromCGRect(view.bounds),
        SGRDynamicBarViewVisible(view), view.hidden, view.alpha, view.userInteractionEnabled,
        view.clipsToBounds, view.translatesAutoresizingMaskIntoConstraints];
}

static void appendOwnedConstraints(NSMutableString *out, UIView *view) {
    for (NSLayoutConstraint *constraint in view.constraints) {
        if (!constraint.active) continue;
        // Attributes are NSLayoutAttribute numbers. Do not use -description: UIKit's descriptions
        // can include label text. Only object identities and layout numbers are needed here.
        [out appendFormat:@"  %@.%ld relation=%ld %@.%ld * %.3f + %.3f priority=%.0f\n",
            diagnosticItem(constraint.firstItem), (long)constraint.firstAttribute, (long)constraint.relation,
            diagnosticItem(constraint.secondItem), (long)constraint.secondAttribute,
            constraint.multiplier, constraint.constant, constraint.priority];
    }
}

static void appendDiagnosticConstraints(NSMutableString *out, UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return;
    appendDiagnosticView(out, @"layout", view);
    appendOwnedConstraints(out, view);
    for (UIView *child in view.subviews) appendDiagnosticConstraints(out, child, depth + 1);
}

static void appendDiagnosticState(NSMutableString *out, BOOL launchEnabled) {
    [out appendFormat:@"== dynamic bar\nlaunch-enabled=%d application-state=%ld sessions=%lu\n", launchEnabled,
        (long)UIApplication.sharedApplication.applicationState, (unsigned long)sg_sessions.allObjects.count];
    for (SGRDynamicBarSession *value in sg_sessions.allObjects) {
        UIViewController *selected = [value.tabs respondsToSelector:@selector(selectedViewController)] ? [(id)value.tabs selectedViewController] : nil;
        UIScrollView *scroll = SGRDynamicBarScrollOwner(selected);
        [out appendFormat:@"session host=%d updating=%d failed-placement=%d last-blockers=0x%x content-blockers=0x%x rejection=%@\n",
            value.host != nil, value.updating, value.failedPlacement, value.lastBlockers,
            SGRDynamicBarContentBlockers(value.player), value.lastRejection ?: @"none"];
        [out appendFormat:@"keyboard=%d full-player=%d transitions=%lu selected=%@ scroll=%@ scene-state=%ld\n",
            value.keyboard, value.fullPlayer != nil, (unsigned long)value.transitions.allObjects.count,
            diagnosticItem(selected), diagnosticItem(scroll), (long)value.window.windowScene.activationState];
        appendDiagnosticView(out, @"stock", value.stockBar);
        appendDiagnosticView(out, @"mirror", value.mirror);
        appendDiagnosticView(out, @"player", value.player.viewIfLoaded);
        appendDiagnosticView(out, @"card", value.card);
        // Include the containing views that can own the player's height constraint, but not the
        // rest of the application's tree or any media labels.
        appendDiagnosticConstraints(out, value.player.viewIfLoaded, 0);
        for (UIView *parent = value.player.viewIfLoaded.superview; parent && parent != value.window; parent = parent.superview) {
            appendDiagnosticView(out, @"ancestor", parent);
            appendOwnedConstraints(out, parent);
        }
    }
}
