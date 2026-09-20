#import <XCTest/XCTest.h>
#import "../../../tweak/Sources/Redesigned/NowPlayingBar/LiveBarLayout.h"

@interface LiveBarLayoutTests : XCTestCase
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIViewController *container;
@property(nonatomic, strong) UIViewController *player;
@property(nonatomic, strong) UIButton *play;
@property(nonatomic, strong) SGRLiveBarLayout *layout;
@end

@implementation LiveBarLayoutTests
- (void)setUp {
    [super setUp];
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
    }
    XCTAssertNotNil(scene);
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    UIViewController *root = [UIViewController new];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    [root.view layoutIfNeeded];
    self.container = [UIViewController new];
    [root addChildViewController:self.container];
    self.container.view.frame = CGRectMake(0, 100, 390, 56);
    [root.view addSubview:self.container.view];
    [self.container didMoveToParentViewController:root];
    self.player = [UIViewController new];
    [self.container addChildViewController:self.player];
    self.player.view.frame = self.container.view.bounds;
    [self.container.view addSubview:self.player.view];
    [self.player didMoveToParentViewController:self.container];
    self.play = [UIButton buttonWithType:UIButtonTypeSystem];
    self.play.frame = CGRectMake(330, 6, 44, 44);
    self.play.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.player.view addSubview:self.play];
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.player.view cardRect:CGRectMake(8, 0, 374, 56)];
}
- (void)tearDown {
    [self.layout restore];
    self.window.hidden = YES;
    self.window = nil;
    [super tearDown];
}
- (CGRect)target { return CGRectMake(80, 210, 280, 56); }
- (void)testPlacementPreservesControllerOwnershipAndOriginalControl {
    XCTAssertTrue([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    XCTAssertEqual(self.player.parentViewController, self.container);
    XCTAssertEqual(self.player.view.superview, self.container.view);
    XCTAssertEqualWithAccuracy(self.play.bounds.size.width, 44, 0.01);
    XCTAssertEqualWithAccuracy(self.play.bounds.size.height, 44, 0.01);
    CGRect card = [self.player.view convertRect:CGRectMake(8, 0, 280, 56) toView:self.window.rootViewController.view];
    XCTAssertTrue(CGRectEqualToRect(card, self.target));
    CGPoint playPoint = [self.play convertPoint:CGPointMake(22, 22) toView:self.window.rootViewController.view];
    XCTAssertEqual([self.layout hitTest:playPoint fromView:self.window.rootViewController.view event:nil], self.play);
}
- (void)testRepeatedPlacementAndRestorationDoNotAccumulateOffsets {
    for (NSUInteger i = 0; i < 30; i++) {
        XCTAssertTrue([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    }
    [self.layout restore];
    XCTAssertTrue(CGRectEqualToRect(self.player.view.frame, self.container.view.bounds));
    XCTAssertFalse(self.layout.placed);
    XCTAssertNil([self.layout hitTest:CGPointMake(100, 230) fromView:self.window.rootViewController.view event:nil]);
}
- (void)testClippedAncestorRejectsPlacementWithoutMutation {
    self.container.view.clipsToBounds = YES;
    CGRect original = self.player.view.frame;
    XCTAssertFalse([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    XCTAssertTrue(CGRectEqualToRect(original, self.player.view.frame));
}
- (void)testStockGeometryReplacementIsNotOverwritten {
    XCTAssertTrue([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    self.player.view.center = CGPointMake(99, 99);
    XCTAssertFalse(self.layout.ownsCurrentGeometry);
    XCTAssertNil([self.layout hitTest:CGPointMake(99, 99) fromView:self.window.rootViewController.view event:nil]);
    [self.layout restore];
    XCTAssertTrue(CGPointEqualToPoint(self.player.view.center, CGPointMake(99, 99)));
    XCTAssertTrue(CGSizeEqualToSize(self.player.view.bounds.size, CGSizeMake(390, 56)));
}
- (void)testDetachAndParentReplacementCannotReuseTheLease {
    XCTAssertTrue([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    [self.player.view removeFromSuperview];
    XCTAssertFalse([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    UIView *newParent = [UIView new];
    [newParent addSubview:self.player.view];
    CGRect frame = self.player.view.frame;
    [self.layout restore];
    XCTAssertTrue(CGRectEqualToRect(frame, self.player.view.frame));
}
- (void)testHiddenAncestorDoesNotExposeOldHitTargets {
    XCTAssertTrue([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    self.container.view.hidden = YES;
    XCTAssertNil([self.layout hitTest:CGPointMake(340, 235) fromView:self.window.rootViewController.view event:nil]);
    XCTAssertFalse([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
}
- (void)testHeightChangeCannotScaleControls {
    CGRect target = self.target;
    target.size.height = 32;
    XCTAssertFalse([self.layout placeCardInRect:target ofView:self.window.rootViewController.view]);
    XCTAssertTrue(CGRectEqualToRect(self.player.view.frame, self.container.view.bounds));
}
- (void)testInlineHeightRelayoutPreservesControlSize {
    CGRect target = self.target;
    target.size.height = 48;
    XCTAssertTrue([self.layout placeCardInRect:target ofView:self.window.rootViewController.view]);
    XCTAssertTrue(CGSizeEqualToSize(self.play.bounds.size, CGSizeMake(44, 44)));
    XCTAssertTrue(CGRectContainsRect(self.player.view.bounds, self.play.frame));
}
- (void)testControlThatDoesNotFitRevokesPlacement {
    self.play.autoresizingMask = UIViewAutoresizingNone;
    XCTAssertFalse([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    XCTAssertFalse(self.layout.placed);
    XCTAssertTrue(CGRectEqualToRect(self.player.view.frame, self.container.view.bounds));
}
- (void)testDisconnectedWindowCannotAcceptPlacement {
    [self.container.view removeFromSuperview];
    XCTAssertFalse([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
}
- (void)testExternalTransformRevokesHitRoutingWithoutOverwritingTheTransform {
    XCTAssertTrue([self.layout placeCardInRect:self.target ofView:self.window.rootViewController.view]);
    CGAffineTransform transform = CGAffineTransformMakeTranslation(0, 10);
    self.player.view.transform = transform;
    XCTAssertFalse(self.layout.ownsCurrentGeometry);
    XCTAssertNil([self.layout hitTest:CGPointMake(340, 235) fromView:self.window.rootViewController.view event:nil]);
    [self.layout restore];
    XCTAssertTrue(CGAffineTransformEqualToTransform(self.player.view.transform, transform));
}
@end
