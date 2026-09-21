#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "../../../tweak/Sources/Redesigned/Navbar/DynamicBarCapabilities.h"

// The ElementView audio fixture reproduces the relevant identities from the 9.1.78 device
// capture documented in ../fixtures/spotify-9.1.78-audio.md. Layout remains synthetic UIKit.
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
- (UIView *)addElementAudio {
    UIViewController *bar = [self addController:@"NowPlaying_BarImpl.NowPlayingBarViewController"];
    UIViewController *content = fixture(@"NowPlaying_BarImpl.ContentViewControllerImplementation", UIViewController.class);
    [bar addChildViewController:content];
    content.view.frame = CGRectMake(0, 0, 386, 56);
    content.view.accessibilityIdentifier = @"SPTNowPlayingBar";
    [bar.view addSubview:content.view];
    [content didMoveToParentViewController:bar];
    UIViewController *duration = fixture(@"NowPlaying_BarImpl.DurationViewController", UIViewController.class);
    [content addChildViewController:duration];
    duration.view.frame = CGRectMake(52, 50, 226, 2);
    [content.view addSubview:duration.view];
    [duration didMoveToParentViewController:content];
    UIView *artwork = fixture(@"_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__", UIView.class);
    artwork.frame = CGRectMake(8, 8, 40, 40);
    [content.view addSubview:artwork];
    UIView *info = fixture(@"_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI24BarTrackInfoElementPropsP_P__", UIView.class);
    info.frame = CGRectMake(56, 12, 230, 31);
    [content.view addSubview:info];
    return content.view;
}
- (UIScrollView *)addScroll:(CGRect)frame height:(CGFloat)height {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:frame];
    scroll.contentSize = CGSizeMake(frame.size.width, height);
    [self.root.view addSubview:scroll];
    return scroll;
}
- (UIViewController *)addElementVideo {
    UIView *card = [self addElementAudio];
    for (UIView *child in card.subviews.copy)
        if ([NSStringFromClass(child.class) containsString:@"ImageDataElementInput"]) [child removeFromSuperview];
    UIViewController *content = self.root.childViewControllers.lastObject.childViewControllers.firstObject;
    UIViewController *video = fixture(@"NowPlaying_BarImpl.BarVideoViewController", UIViewController.class);
    [content addChildViewController:video];
    video.view.frame = CGRectMake(0, 0, 75, 56);
    [card addSubview:video.view];
    [video didMoveToParentViewController:content];
    UIView *surface = fixture(@"SPTVideoSurfaceImpl", UIView.class);
    surface.frame = video.view.bounds;
    [video.view addSubview:surface];
    return video;
}
- (void)testCapturedVideoRequiresItsLiveSurfaceAndVisibleTrackInfo {
    UIViewController *video = [self addElementVideo];
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    UIView *surface = video.view.subviews.firstObject;
    surface.hidden = YES;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
    surface.hidden = NO;
    UIView *card = video.view.superview;
    UIView *info = card.subviews[1]; // duration, track info, video
    info.alpha = 0;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
    info.alpha = 1;
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
}
- (void)testUnrelatedSurfaceCannotQualifyAVideoController {
    UIViewController *video = [self addElementVideo];
    [video.view.superview addSubview:video.view.subviews.firstObject];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
}
- (void)testVideoWithJamStillRequiresExpandedPresentation {
    UIViewController *video = [self addElementVideo];
    UIView *badge = fixture(@"NowPlaying_ECMKit.JamListeningAlongLiveBadgeView", UIView.class);
    badge.frame = CGRectMake(80, 10, 44, 20);
    [video.view.superview addSubview:badge];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarExtraContent);
    badge.hidden = YES;
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
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
- (void)testCapturedElementAudioDoesNotRequireACoverController {
    [self addElementAudio];
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
}
- (void)testCapturedElementAudioRequiresVisibleArtworkAndTrackInfoInTheStockCard {
    UIView *card = [self addElementAudio];
    UIView *info = card.subviews.lastObject;
    info.alpha = 0;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
    info.alpha = 1;
    [self.root.view addSubview:info];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
    [card addSubview:info];
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    card.accessibilityIdentifier = nil;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarUnknownContent);
}
- (void)testDemangledVideoIdentityRevokesCapturedAudioEligibility {
    [self addElementAudio];
    UIViewController *video = [self addController:@"NowPlaying_BarImpl.BarVideoViewController"];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
    video.view.alpha = 0;
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    video.view.alpha = 1;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
}
- (void)testVideoSubclassAlsoRevokesEligibility {
    [self addElementAudio];
    Class videoType = [fixture(@"_TtC18NowPlaying_BarImpl22BarVideoViewController", UIViewController.class) class];
    fixture(@"ProbeVideoSubclass", videoType);
    [self addController:@"ProbeVideoSubclass"];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarVideo);
}
- (void)testDormantJamBadgeInCapturedAudioDoesNotBlockUntilVisible {
    UIView *card = [self addElementAudio];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(56, 20, 44, 16)];
    container.hidden = YES;
    [card addSubview:container];
    UIView *badge = fixture(@"NowPlaying_ECMKit.JamListeningAlongLiveBadgeView", UIView.class);
    badge.frame = container.bounds;
    [container addSubview:badge];
    XCTAssertEqual(SGRDynamicBarContentBlockers(self.root), 0u);
    container.hidden = NO;
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarExtraContent);
}
- (void)testDemangledAttachmentViewRequiresExpandedPresentation {
    UIView *card = [self addElementAudio];
    UIView *attachment = fixture(@"NowPlaying_BarImpl.AttachmentView", UIView.class);
    attachment.frame = CGRectMake(0, 0, 50, 30);
    [card addSubview:attachment];
    XCTAssertTrue(SGRDynamicBarContentBlockers(self.root) & SGRDynamicBarExtraContent);
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
