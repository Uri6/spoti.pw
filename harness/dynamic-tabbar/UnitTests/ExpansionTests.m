#import <XCTest/XCTest.h>
#import "Redesigned/Navbar/DynamicBarExpansion.h"
#import "Redesigned/Navbar/DynamicBarScrollDriver.h"

@interface ExpansionTests : XCTestCase
@end
@implementation ExpansionTests
- (void)testEligibilityRefreshPreservesExpansionUntilScrollOwnerChanges {
    UITabBarController *controller = [UITabBarController new];
    controller.viewControllers = @[[UIViewController new]];
    SGRDynamicBarScrollDriver *driver = [SGRDynamicBarScrollDriver new];
    UIScrollView *first = [UIScrollView new], *next = [UIScrollView new];
    driver.tabController = controller;
    driver.scrollView = first;
    driver.permitted = YES;
    XCTAssertTrue(SGRDynamicBarExpand(controller, NO));
    // Player/page layout refreshes eligibility during the same reverse drag.
    driver.scrollView = first;
    driver.permitted = YES;
    XCTAssertEqual(controller.tabBarMinimizeBehavior, UITabBarMinimizeBehaviorNever);
    // Changing pages removes that gesture's target and must re-arm the new relationship.
    driver.scrollView = next;
    XCTAssertEqual(controller.tabBarMinimizeBehavior, UITabBarMinimizeBehaviorOnScrollDown);
    driver.permitted = NO;
    XCTAssertEqual(controller.tabBarMinimizeBehavior, UITabBarMinimizeBehaviorNever);
    [driver invalidate];
}
- (void)testNonanimatedExpansionUsesPublicPolicy {
    UITabBarController *controller = [UITabBarController new];
    controller.viewControllers = @[[UIViewController new]];
    [controller loadViewIfNeeded];
    controller.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
    XCTAssertTrue(SGRDynamicBarExpand(controller, NO));
    XCTAssertEqual(controller.tabBarMinimizeBehavior, UITabBarMinimizeBehaviorNever);
    XCTAssertTrue(SGRDynamicBarExpand(controller, NO));
    XCTAssertEqual(controller.selectedIndex, 0);
    XCTAssertFalse(SGRDynamicBarExpand(nil, NO));
}
- (void)testUnrelatedNoAnimationBlocksRetainTheirBehaviorAfterExpansion {
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (id)candidate; break; }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    UITabBarController *controller = [UITabBarController new];
    controller.viewControllers = @[[UIViewController new]];
    window.rootViewController = controller;
    [window makeKeyAndVisible];
    [controller.view layoutIfNeeded];
    controller.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
    XCTAssertTrue(SGRDynamicBarExpand(controller, YES));
    BOOL enabled = UIView.areAnimationsEnabled;
    [UIView performWithoutAnimation:^{ XCTAssertFalse(UIView.areAnimationsEnabled); }];
    XCTAssertEqual(UIView.areAnimationsEnabled, enabled);
    window.hidden = YES;
}
@end
