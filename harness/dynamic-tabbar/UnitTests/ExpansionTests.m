#import <XCTest/XCTest.h>
#import <objc/message.h>
#import "Redesigned/Navbar/DynamicBarExpansion.h"

@interface UnavailableExpansionBar : UITabBar
@end
@implementation UnavailableExpansionBar
- (BOOL)respondsToSelector:(SEL)selector {
    if ([NSStringFromSelector(selector) isEqualToString:@"_setMinimized:"]) return NO;
    return [super respondsToSelector:selector];
}
@end

@interface ExpansionTests : XCTestCase
@end
@implementation ExpansionTests
- (void)testNativeRuntimeHasTheVerifiedExpansionContract {
    XCTAssertTrue(SGRDynamicBarCanExpand([UITabBar new]));
    XCTAssertFalse(SGRDynamicBarCanExpand(nil));
    XCTAssertFalse(SGRDynamicBarCanExpand((id)[NSObject new]));
    XCTAssertFalse(SGRDynamicBarCanExpand([UnavailableExpansionBar new]));
}
- (void)testExplicitExpansionPreservesTheScrollingPolicy {
    UITabBarController *controller = [UITabBarController new];
    controller.viewControllers = @[[UIViewController new]];
    [controller loadViewIfNeeded];
    [controller.view layoutIfNeeded];
    controller.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
    XCTAssertTrue(SGRDynamicBarCanExpand(controller.tabBar));
    ((void (*)(id, SEL, BOOL))objc_msgSend)(controller.tabBar, NSSelectorFromString(@"_setMinimized:"), YES);
    XCTAssertTrue(SGRDynamicBarIsMinimized(controller.tabBar));
    XCTAssertTrue(SGRDynamicBarExpand(controller, NO));
    XCTAssertFalse(SGRDynamicBarIsMinimized(controller.tabBar));
    XCTAssertEqual(controller.tabBarMinimizeBehavior, UITabBarMinimizeBehaviorOnScrollDown);
    // Repeated requests are no-ops; they do not restart native transitions or change selection.
    XCTAssertTrue(SGRDynamicBarExpand(controller, NO));
    XCTAssertEqual(controller.selectedIndex, 0);
}
@end
