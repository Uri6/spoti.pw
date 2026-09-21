#import <UIKit/UIKit.h>

// Expands only our owned native tab controller using the public minimize policy. The animation
// compatibility scope suppresses UIKit's no-animation wrapper only during that one policy write.
BOOL SGRDynamicBarExpand(UITabBarController *controller, BOOL animated);
NSUInteger SGRDynamicBarExpansionWrapperCount(void);
