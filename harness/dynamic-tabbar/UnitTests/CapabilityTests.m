#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "../../../tweak/Sources/Redesigned/Navbar/DynamicBarCapabilities.h"

// Synthetic trees exercise the classifier's rejection rules, not Spotify's actual hierarchy.
// Names come from 9.1.78 metadata; their co-occurrence must still be checked on a physical device.
static id fixture(NSString *name, Class superclass) {
    Class cls = NSClassFromString(name);
    if (!cls) { cls = objc_allocateClassPair(superclass, name.UTF8String, 0); objc_registerClassPair(cls); }
    return [cls new];
}

@interface CapabilityTests : XCTestCase
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIViewController *root;
@end

@implementation CapabilityTests
- (void)setUp {
    [super setUp];
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
    }
    XCTAssertNotNil(scene);
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.root = [UIViewController new];
    self.window.rootViewController = self.root;
    [self.window makeKeyAndVisible];
    [self.root.view layoutIfNeeded];
}
- (void)tearDown {
    self.window.hidden = YES;
    self.window = nil;
    [super tearDown];
}
- (UIViewController *)addController:(NSString *)name {
    UIViewController *vc = fixture(name, UIViewController.class);
    [self.root addChildViewController:vc];
    vc.view.frame = self.root.view.bounds;
    [self.root.view addSubview:vc.view];
    [vc didMoveToParentViewController:self.root];
    return vc;
}
- (void)addAudio {
    [self addController:@"_TtC18NowPlaying_BarImpl25BarCoverArtViewController"];
    [self addController:@"_TtC18NowPlaying_BarImpl35ContentViewControllerImplementation"];
}
- (UIScrollView *)addScroll:(CGRect)frame height:(CGFloat)height {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:frame];
    scroll.contentSize = CGSizeMake(frame.size.width, height);
    [self.root.view addSubview:scroll];
    return scroll;
}
- (void)testUnknownAndUnloadedControllersFailWithoutLoadingTheirViews {
    UIViewController *unloaded = [UIViewController new];
    XCTAssertTrue(SGRDynamicBarContentBlockers(unloaded) & SGRDynamicBarUnknownContent);
    XCTAssertNil(SGRDynamicBarScrollOwner(unloaded));
    XCTAssertFalse(unloaded.isViewLoaded);
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
}
- (void)testAudioRequiresBothVisiblePositiveIdentities {
    UIViewController *cover = [self addController:@"_TtC18NowPlaying_BarImpl25BarCoverArtViewController"];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
    [self addController:@"_TtC18NowPlaying_BarImpl35ContentViewControllerImplementation"];
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    cover.view.alpha = 0;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
}
- (void)testVideoAppearingOnTheSameAudioTreeRevokesEligibility {
    [self addAudio];
    UIViewController *video = [self addController:@"_TtC18NowPlaying_BarImpl22BarVideoViewController"];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
    video.view.hidden = YES;
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    video.view.hidden = NO;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
}
- (void)testAttachmentControllersRequireExpandedPresentation {
    [self addAudio];
    [self addController:@"ProbeSocialListeningAttachmentController"];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarExtraContent);
}
- (void)testJamHatAndAttachmentViewsRequireExpandedPresentation {
    [self addAudio];
    for (NSString *name in @[@"_TtC17NowPlaying_ECMKit30JamListeningAlongLiveBadgeView",
                            @"ProbeNowPlayingBarHatElementUI", @"_TtC18NowPlaying_BarImpl14AttachmentView"]) {
        UIView *extra = fixture(name, UIView.class);
        extra.frame = CGRectMake(0, 0, 50, 30);
        [self.root.view addSubview:extra];
        XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarExtraContent, @"%@", name);
        [extra removeFromSuperview];
        XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    }
}
- (void)testDetachedOrHiddenRootCannotSupplyCapabilities {
    [self addAudio];
    self.root.view.hidden = YES;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
    self.root.view.hidden = NO;
    [self.root.view removeFromSuperview];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
}
- (void)testDominantVerticalListOwnsScrollWithoutChangingItsDelegate {
    UIScrollView *scroll = [self addScroll:self.root.view.bounds height:3000];
    id delegate = scroll.delegate;
    XCTAssertEqual(SGRDynamicBarScrollOwner(self.root), scroll);
    XCTAssertEqual(scroll.delegate, delegate);
}
- (void)testHorizontalCarouselAndShortPageCannotOwnScroll {
    UIScrollView *scroll = [self addScroll:CGRectMake(0, 100, self.root.view.bounds.size.width, 180) height:180];
    scroll.contentSize = CGSizeMake(2000, 180);
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
    scroll.frame = self.root.view.bounds;
    scroll.contentSize = scroll.bounds.size;
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
}
- (void)testTwoDominantListsAreAmbiguous {
    [self addScroll:self.root.view.bounds height:3000];
    [self addScroll:self.root.view.bounds height:3000];
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
}
- (void)testSmallNestedListDoesNotStealOwnership {
    UIScrollView *outer = [self addScroll:self.root.view.bounds height:3000];
    UIScrollView *inner = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 200, 250, 150)];
    inner.contentSize = CGSizeMake(250, 1000);
    [outer addSubview:inner];
    XCTAssertEqual(SGRDynamicBarScrollOwner(self.root), outer);
}
- (void)testDisabledHiddenAndFullPlayerScrollViewsCannotOwnScroll {
    UIScrollView *scroll = [self addScroll:self.root.view.bounds height:3000];
    scroll.scrollEnabled = NO;
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
    scroll.scrollEnabled = YES;
    scroll.hidden = YES;
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
    scroll.hidden = NO;
    scroll.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
}
- (void)testReplacingPageScrollViewReleasesThePreviousOwner {
    UIScrollView *first = [self addScroll:self.root.view.bounds height:3000];
    XCTAssertEqual(SGRDynamicBarScrollOwner(self.root), first);
    [first removeFromSuperview];
    XCTAssertNil(SGRDynamicBarScrollOwner(self.root));
    UIScrollView *second = [self addScroll:self.root.view.bounds height:3000];
    XCTAssertEqual(SGRDynamicBarScrollOwner(self.root), second);
}
@end
