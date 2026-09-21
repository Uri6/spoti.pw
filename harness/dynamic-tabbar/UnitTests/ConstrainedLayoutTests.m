#import <XCTest/XCTest.h>
#import "../App/FixtureAudioPlayer.h"
#import "Redesigned/NowPlayingBar/LiveBarLayout.h"

@interface ConstrainedLayoutTests : XCTestCase
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UIView *parent;
@property(nonatomic, strong) FixtureAudioPlayer *fixture;
@property(nonatomic, strong) SGRLiveBarLayout *layout;
@end
@implementation ConstrainedLayoutTests
- (void)setUp {
    [super setUp];
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (id)candidate; break; }
    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    self.parent = [[UIView alloc] initWithFrame:CGRectMake(0, 100, 402, 56)];
    [self.window.rootViewController.view addSubview:self.parent];
    self.fixture = [[FixtureAudioPlayer alloc] initInParent:self.parent];
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
}
- (void)tearDown {
    [self.layout restore];
    self.window.hidden = YES;
    self.window = nil;
    [super tearDown];
}
- (BOOL)place:(CGFloat)width {
    return [self.layout placeCardInRect:CGRectMake(30, 250, width, 48) ofView:self.window.rootViewController.view];
}
- (void)testCapturedConstraintsResizeTheRealCardAndKeepOriginalControl {
    XCTAssertTrue([self place:360], @"%@", self.layout.rejectionReason);
    XCTAssertEqual(self.fixture.source.superview, self.parent);
    XCTAssertEqualWithAccuracy(self.fixture.card.bounds.size.width, 360, 0.5);
    XCTAssertEqualWithAccuracy(self.fixture.card.bounds.size.height, 48, 0.5);
    XCTAssertEqualWithAccuracy(self.fixture.artwork.bounds.size.height, 40, 0.5);
    XCTAssertEqualWithAccuracy(self.fixture.play.bounds.size.width, 44, 0.5);
    XCTAssertEqualWithAccuracy(self.fixture.play.bounds.size.height, 40, 0.5);
    XCTAssertTrue(self.layout.ownsCurrentGeometry);
    UIView *host = self.window.rootViewController.view;
    CGPoint point = [self.fixture.play convertPoint:CGPointMake(22, 20) toView:host];
    UIView *hit = [self.layout hitTest:point fromView:host event:nil];
    XCTAssertEqual(hit, self.fixture.play);
    [(UIButton *)hit sendActionsForControlEvents:UIControlEventTouchUpInside];
    XCTAssertEqualObjects(self.fixture.play.accessibilityValue, @"1");
}
- (void)testRepeatedInlineWidthsRestoreEveryLeasedConstraint {
    for (NSUInteger i = 0; i < 20; i++) XCTAssertTrue([self place:i % 2 ? 260 : 360], @"%@", self.layout.rejectionReason);
    [self.layout restore];
    for (NSLayoutConstraint *c in self.fixture.rootPins) XCTAssertTrue(c.active);
    XCTAssertEqual(self.fixture.cardHeight.constant, 56);
    XCTAssertEqual(self.fixture.artTop.constant, 8);
    XCTAssertTrue(CGRectEqualToRect(self.fixture.source.frame, self.parent.bounds));
    XCTAssertEqualWithAccuracy(self.fixture.card.bounds.size.height, 56, 0.5);
    XCTAssertEqualWithAccuracy(self.fixture.card.bounds.size.width, 386, 0.5);
}
- (void)testSpotifyHeightChangeRevokesLeaseAndIsNotOverwritten {
    XCTAssertTrue([self place:360]);
    self.fixture.cardHeight.constant = 60;
    XCTAssertFalse(self.layout.ownsCurrentGeometry);
    XCTAssertFalse([self place:260]);
    [self.layout restore];
    XCTAssertEqual(self.fixture.cardHeight.constant, 60);
    XCTAssertEqual(self.fixture.artTop.constant, 8);
}
- (void)testReparentingDoesNotReactivateCrossHierarchyPins {
    XCTAssertTrue([self place:360]);
    UIView *replacement = [UIView new];
    [replacement addSubview:self.fixture.source];
    [self.layout restore];
    for (NSLayoutConstraint *c in self.fixture.rootPins) XCTAssertFalse(c.active);
    XCTAssertEqual(self.fixture.source.superview, replacement);
}
- (void)testUnknownExternalConstraintRejectsWithoutAnyMutation {
    NSLayoutConstraint *extra = [self.fixture.source.centerXAnchor constraintEqualToAnchor:self.parent.centerXAnchor];
    extra.active = YES;
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
    XCTAssertFalse([self place:360]);
    for (NSLayoutConstraint *c in self.fixture.rootPins) XCTAssertTrue(c.active);
    XCTAssertEqual(self.fixture.cardHeight.constant, 56);
    XCTAssertEqual(self.fixture.artTop.constant, 8);
}
- (void)testUnrecognizedContentDoesNotLeaseConstraints {
    self.fixture.card.accessibilityIdentifier = @"Unknown";
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
    XCTAssertFalse([self place:360]);
    XCTAssertEqual(self.fixture.cardHeight.constant, 56);
}
- (void)testRightToLeftCardPlacementAndRestoration {
    self.parent.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [self.parent setNeedsLayout];
    [self.parent layoutIfNeeded];
    XCTAssertTrue([self place:260], @"%@", self.layout.rejectionReason);
    CGRect actual = [self.fixture.card convertRect:self.fixture.card.bounds toView:self.window.rootViewController.view];
    XCTAssertEqualWithAccuracy(actual.origin.x, 30, 0.5);
    [self.layout restore];
    XCTAssertEqualWithAccuracy(self.fixture.card.bounds.size.width, 386, 0.5);
}
- (void)testParentSizedByOriginalPlayerRetainsItsHeightAndWindowPosition {
    // Spotify's parent is Auto Layout, with its height supplied only by the source's edge pins
    // and 56 pt height. A fixed-frame parent misses the sizing contribution removed by a lease.
    self.parent.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *root = self.window.rootViewController.view;
    [NSLayoutConstraint activateConstraints:@[[self.parent.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.parent.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.parent.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-91]]];
    [root layoutIfNeeded];
    CGRect parentFrame = self.parent.frame;
    XCTAssertFalse(self.parent.hasAmbiguousLayout);
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
    for (NSUInteger i = 0; i < 3; i++) {
        XCTAssertTrue([self place:i % 2 ? 260 : 360], @"%@", self.layout.rejectionReason);
        [root setNeedsLayout];
        [root layoutIfNeeded];
        XCTAssertFalse(self.parent.hasAmbiguousLayout);
        XCTAssertTrue(CGRectEqualToRect(self.parent.frame, parentFrame));
        XCTAssertTrue(self.layout.ownsCurrentGeometry);
        CGRect card = [self.fixture.card convertRect:self.fixture.card.bounds toView:root];
        XCTAssertEqualWithAccuracy(card.origin.y, 250, 0.5);
    }
    [self.layout restore];
    [root layoutIfNeeded];
    XCTAssertFalse(self.parent.hasAmbiguousLayout);
    XCTAssertTrue(CGRectEqualToRect(self.parent.frame, parentFrame));
    XCTAssertEqualWithAccuracy(self.fixture.card.bounds.size.height, 56, 0.5);
}
- (void)installVideo:(CGFloat)ratio {
    [self.layout restore];
    [self.fixture.source removeFromSuperview];
    self.fixture = [[FixtureAudioPlayer alloc] initInParent:self.parent videoAspectRatio:ratio];
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
}
- (void)testVideoSurfaceRemainsLiveAndPreservesAspectAcrossWidths {
    for (NSNumber *ratioValue in @[@(4.0/3), @(16.0/9), @(9.0/16)]) {
        CGFloat ratio = ratioValue.doubleValue;
        [self installVideo:ratio];
        UIView *surface = self.fixture.videoSurface;
        UIView *surfaceParent = surface.superview;
        CALayer *layer = surface.layer;
        for (NSNumber *width in @[@360, @260, @360]) {
            XCTAssertTrue([self place:width.doubleValue], @"%@", self.layout.rejectionReason);
            XCTAssertEqual(self.fixture.videoSurface, surface);
            XCTAssertEqual(surface.superview, surfaceParent);
            XCTAssertEqual(surface.layer, layer);
            XCTAssertEqualWithAccuracy(surface.bounds.size.height, 48, 0.5);
            XCTAssertEqualWithAccuracy(surface.bounds.size.width / surface.bounds.size.height, ratio, 0.01);
            XCTAssertEqualWithAccuracy(self.fixture.play.bounds.size.height, 44, 0.5);
        }
        [self.layout restore];
        XCTAssertEqualWithAccuracy(surface.bounds.size.height, 56, 0.5);
        XCTAssertEqualWithAccuracy(surface.bounds.size.width, 56 * ratio, 0.5);
        XCTAssertTrue(self.fixture.videoAspect.active);
    }
}
- (void)testExternalVideoAspectReplacementRevokesLeaseWithoutOverwritingIt {
    [self installVideo:4.0/3];
    XCTAssertTrue([self place:360]);
    self.fixture.videoAspect.active = NO;
    NSLayoutConstraint *replacement = [self.fixture.videoSurface.widthAnchor constraintEqualToAnchor:self.fixture.videoSurface.heightAnchor multiplier:16.0/9];
    replacement.active = YES;
    XCTAssertFalse(self.layout.ownsCurrentGeometry);
    [self.layout restore];
    XCTAssertFalse(self.fixture.videoAspect.active);
    XCTAssertTrue(replacement.active);
    XCTAssertEqualWithAccuracy(self.fixture.videoSurface.bounds.size.width / self.fixture.videoSurface.bounds.size.height, 16.0/9, 0.01);
    // A media-change hook releases before Spotify mutates. Reacquiring sees the new natural ratio.
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
    XCTAssertTrue([self place:260], @"%@", self.layout.rejectionReason);
    XCTAssertEqualWithAccuracy(self.fixture.videoSurface.bounds.size.width / self.fixture.videoSurface.bounds.size.height, 16.0/9, 0.01);
}
- (void)testMissingVideoAspectRejectsWithoutMutatingTheNaturalCard {
    [self installVideo:4.0/3];
    self.fixture.videoAspect.active = NO;
    [self.parent layoutIfNeeded];
    self.layout = [[SGRLiveBarLayout alloc] initWithSource:self.fixture.source cardView:self.fixture.card];
    XCTAssertFalse([self place:360]);
    XCTAssertEqual(self.fixture.cardHeight.constant, 56);
    XCTAssertFalse(self.fixture.videoAspect.active);
}
- (void)testUnsupportedVideoAspectDoesNotMutateTheSurface {
    [self installVideo:4];
    XCTAssertFalse([self place:260]);
    XCTAssertTrue(self.fixture.videoAspect.active);
    XCTAssertEqualWithAccuracy(self.fixture.videoSurface.bounds.size.width, 224, 0.5);
}
- (void)testVideoSurfaceDetachmentRevokesTheLease {
    [self installVideo:16.0/9];
    XCTAssertTrue([self place:360]);
    [self.fixture.videoSurface removeFromSuperview];
    XCTAssertFalse(self.layout.ownsCurrentGeometry);
    [self.layout restore];
    XCTAssertTrue(self.fixture.videoAspect.active);
    XCTAssertNil(self.fixture.videoSurface.superview);
}
@end
