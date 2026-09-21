#import <UIKit/UIKit.h>

// Private UIKit compatibility boundary, limited to the native tab bar we own. Missing or
// changed method signatures disable minimization rather than leave an unexpandable bar.
BOOL SGRDynamicBarCanExpand(UITabBar *bar);
BOOL SGRDynamicBarIsMinimized(UITabBar *bar);
BOOL SGRDynamicBarExpand(UITabBarController *controller, BOOL animated);
