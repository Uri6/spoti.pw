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
@end
