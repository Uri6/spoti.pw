#import <XCTest/XCTest.h>
#import "Redesigned/Navbar/DynamicBarExpansion.h"

@interface ExpansionTests : XCTestCase
@end
@implementation ExpansionTests
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
