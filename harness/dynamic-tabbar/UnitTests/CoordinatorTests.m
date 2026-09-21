#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "Redesigned/Navbar/DynamicBarCoordinator.h"
#import "Redesigned/Navbar/DynamicBarHost.h"
#import "Core/SGLog.h"

@interface FixtureTabs : UIViewController
@property(nonatomic, strong) UIViewController *selectedViewController;
@end
@implementation FixtureTabs
@end

@interface CoordinatorTests : XCTestCase
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) FixtureTabs *tabs;
@property(nonatomic, strong) UIViewController *player;
@property(nonatomic, strong) UIView *card;
@property(nonatomic, strong) UIView *stock;
@property(nonatomic, strong) UITabBar *mirror;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic) CGRect naturalFrame;
@end

@implementation CoordinatorTests
- (void)add:(UIViewController *)child to:(UIViewController *)parent frame:(CGRect)frame {
    [parent addChildViewController:child];
    child.view.frame = frame;
    [parent.view addSubview:child.view];
    [child didMoveToParentViewController:parent];
}
- (UIViewController *)addPlayerController:(NSString *)name {
    Class cls = NSClassFromString(name);
    if (!cls) { cls = objc_allocateClassPair(UIViewController.class, name.UTF8String, 0); objc_registerClassPair(cls); }
    UIViewController *child = [cls new];
    [self add:child to:self.player frame:CGRectMake(8, 0, 44, 44)];
    return child;
}
- (void)setUp {
    [super setUp];
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
    }
    XCTAssertNotNil(scene);
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.tabs = [FixtureTabs new];
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];
    [self.tabs.view layoutIfNeeded];
    UIViewController *page = [UIViewController new];
    UIScrollView *scroll = [UIScrollView new];
    scroll.contentSize = CGSizeMake(self.window.bounds.size.width, 3000);
    page.view = scroll;
    [self add:page to:self.tabs frame:self.tabs.view.bounds];
    self.tabs.selectedViewController = page;
    self.player = [UIViewController new];
    self.naturalFrame = CGRectMake(0, 100, self.window.bounds.size.width, 64);
    [self add:self.player to:self.tabs frame:self.naturalFrame];
    self.card = [[UIView alloc] initWithFrame:CGRectMake(8, 0, self.naturalFrame.size.width - 16, 56)];
    self.card.accessibilityIdentifier = @"SPTNowPlayingBar";
    self.card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.player.view addSubview:self.card];
    [self addPlayerController:@"NowPlaying_BarImpl.ContentViewControllerImplementation"];
    // The device's ordinary audio uses ElementViews, without a cover-art controller.
    for (NSString *name in @[@"_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__",
                            @"_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI24BarTrackInfoElementPropsP_P__"]) {
        Class cls = NSClassFromString(name);
        if (!cls) { cls = objc_allocateClassPair(UIView.class, name.UTF8String, 0); objc_registerClassPair(cls); }
        UIView *element = [[cls alloc] initWithFrame:CGRectMake(8, 8, 40, 40)];
        [self.card addSubview:element];
    }
    self.glass = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.glass.frame = self.card.frame;
    [self.player.view insertSubview:self.glass atIndex:0];
    self.stock = [[UIView alloc] initWithFrame:CGRectMake(0, self.window.bounds.size.height - 83, self.window.bounds.size.width, 83)];
    [self.tabs.view addSubview:self.stock];
    self.mirror = [[UITabBar alloc] initWithFrame:self.stock.bounds];
    self.mirror.items = @[[[UITabBarItem alloc] initWithTitle:@"Home" image:[UIImage systemImageNamed:@"house"] tag:0]];
    self.mirror.selectedItem = self.mirror.items.firstObject;
    [self.stock addSubview:self.mirror];
    [self refresh];
}
- (void)refresh {
    SGRDynamicBarUpdatePlayer(self.player, self.card, self.glass);
    SGRDynamicBarUpdateTabs(self.tabs, self.stock, self.mirror, @[self.stock], ^(UIView *source) {});
}
- (SGRDynamicBarHost *)host {
    for (UIViewController *child in self.tabs.childViewControllers) if ([child isKindOfClass:SGRDynamicBarHost.class]) return (id)child;
    return nil;
}
- (void)tearDown {
    self.stock.hidden = YES;
    [self refresh];
    self.window.hidden = YES;
    self.window = nil;
    [super tearDown];
}
- (void)assertRestored {
    XCTAssertNil(self.host);
    XCTAssertEqualWithAccuracy(self.mirror.alpha, 1, 0.001);
    XCTAssertTrue(self.mirror.userInteractionEnabled);
    XCTAssertEqualWithAccuracy(self.glass.alpha, 1, 0.001);
    XCTAssertTrue(CGRectEqualToRect(self.player.view.frame, self.naturalFrame));
    XCTAssertEqual(self.player.parentViewController, self.tabs);
}
- (void)testAudioAttachesAndVideoRestoresOriginalPresentation {
    XCTAssertNotNil(self.host);
    XCTAssertEqualWithAccuracy(self.mirror.alpha, 0, 0.001);
    [self addPlayerController:@"_TtC18NowPlaying_BarImpl22BarVideoViewController"];
    [self refresh];
    [self assertRestored];
}
- (void)testSnapshotSetupSuspendsBeforeAnAnimatorHasItsBar {
    XCTAssertNotNil(self.host);
    NSObject *transition = [NSObject new];
    SGRDynamicBarBeginTransition(nil, transition);
    [self assertRestored];
    [self refresh];
    XCTAssertNil(self.host);
    SGRDynamicBarEndTransition(transition);
    XCTAssertNotNil(self.host);
}
- (void)testHiddenStockBarRestoresAndCanAttachWhenVisibleAgain {
    XCTAssertNotNil(self.host);
    self.stock.hidden = YES;
    [self refresh];
    [self assertRestored];
    self.stock.hidden = NO;
    [self refresh];
    XCTAssertNotNil(self.host);
}
- (void)testFullPlayerAppearanceAndCompletionReleaseSuspension {
    XCTAssertNotNil(self.host);
    UIViewController *fullPlayer = [UIViewController new];
    [self add:fullPlayer to:self.tabs frame:self.tabs.view.bounds];
    SGRDynamicBarPlayerVisibility(fullPlayer, YES);
    [self assertRestored];
    SGRDynamicBarPlayerVisibility(fullPlayer, NO);
    XCTAssertNotNil(self.host);
}
- (void)testKeyboardRestoresAndResumesAfterHiding {
    XCTAssertNotNil(self.host);
    CGRect keyboard = CGRectMake(0, self.window.bounds.size.height - 300, self.window.bounds.size.width, 300);
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil
        userInfo:@{UIKeyboardFrameEndUserInfoKey: [NSValue valueWithCGRect:keyboard]}];
    [self assertRestored];
    keyboard.origin.y = self.window.bounds.size.height + 10;
    [NSNotificationCenter.defaultCenter postNotificationName:UIKeyboardWillChangeFrameNotification object:nil
        userInfo:@{UIKeyboardFrameEndUserInfoKey: [NSValue valueWithCGRect:keyboard]}];
    XCTAssertNotNil(self.host);
}
- (void)testRestorationDoesNotOverwriteARecomputedGlassFrame {
    XCTAssertNotNil(self.host);
    CGRect updated = CGRectMake(3, 4, 100, 72);
    self.glass.frame = updated;
    NSObject *transition = [NSObject new];
    SGRDynamicBarBeginTransition(self.stock, transition);
    XCTAssertTrue(CGRectEqualToRect(self.glass.frame, updated));
    [self assertRestored];
}
- (void)testReplacingTheMirrorReleasesTheOldMirror {
    XCTAssertNotNil(self.host);
    UITabBar *old = self.mirror;
    [old removeFromSuperview];
    self.mirror = [[UITabBar alloc] initWithFrame:self.stock.bounds];
    self.mirror.items = old.items;
    self.mirror.selectedItem = self.mirror.items.firstObject;
    [self.stock addSubview:self.mirror];
    [self refresh];
    XCTAssertEqualWithAccuracy(old.alpha, 1, 0.001);
    XCTAssertTrue(old.userInteractionEnabled);
    XCTAssertNotNil(self.host);
    XCTAssertEqualWithAccuracy(self.mirror.alpha, 0, 0.001);
}
- (void)testDiagnosticSnapshotIsReadOnlyAndOmitsMediaText {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 20)];
    label.text = @"Private fixture media title";
    label.accessibilityIdentifier = @"Private fixture account identifier";
    [self.card addSubview:label];
    SGRDynamicBarHost *host = self.host;
    CGRect frame = self.player.view.frame;
    NSMutableString *report = [NSMutableString string];
    [NSNotificationCenter.defaultCenter postNotificationName:SGDiagnosticSnapshotNotification object:report];
    XCTAssertTrue([report containsString:@"== dynamic bar"]);
    XCTAssertTrue([report containsString:@"launch-enabled=1"]);
    XCTAssertFalse([report containsString:label.text]);
    XCTAssertFalse([report containsString:label.accessibilityIdentifier]);
    XCTAssertEqual(self.host, host);
    XCTAssertTrue(CGRectEqualToRect(self.player.view.frame, frame));
    XCTAssertEqualWithAccuracy(self.mirror.alpha, 0, 0.001);
}
- (void)drainReadinessRefresh {
    XCTestExpectation *done = [self expectationWithDescription:@"coalesced readiness"];
    dispatch_async(dispatch_get_main_queue(), ^{ [done fulfill]; });
    [self waitForExpectations:@[done] timeout:2];
}
- (void)testAsyncFeedBecomingScrollableAttachesWithoutAnotherBarLayout {
    UIScrollView *scroll = (id)self.tabs.selectedViewController.view;
    scroll.contentSize = CGSizeZero;
    [self refresh];
    [self assertRestored];
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, 3000);
    SGRDynamicBarScrollChanged(scroll);
    SGRDynamicBarScrollChanged(scroll); // repeated changes in one run loop are coalesced
    [self drainReadinessRefresh];
    XCTAssertNotNil(self.host);
    XCTAssertEqual(self.host.observedScrollView, scroll);
}
- (void)testDetachedScrollOwnerReleasesHostAfterAttachmentEvent {
    UIScrollView *scroll = (id)self.tabs.selectedViewController.view;
    [scroll removeFromSuperview];
    SGRDynamicBarScrollChanged(scroll);
    [self drainReadinessRefresh];
    [self assertRestored];
}
- (void)testUnrelatedScrollEventsCannotRefreshTheSelectedPage {
    UIScrollView *scroll = (id)self.tabs.selectedViewController.view;
    scroll.contentSize = CGSizeZero;
    [self refresh];
    [self assertRestored];
    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, 3000);
    UIScrollView *other = [[UIScrollView alloc] initWithFrame:self.tabs.view.bounds];
    [self.tabs.view addSubview:other];
    SGRDynamicBarScrollChanged(other);
    [self drainReadinessRefresh];
    XCTAssertNil(self.host);
    SGRDynamicBarScrollChanged(scroll);
    [self drainReadinessRefresh];
    XCTAssertNotNil(self.host);
}
@end
