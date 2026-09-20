#import <UIKit/UIKit.h>
#import "DynamicBarPolicy.h"

// Inspection only: never loads a controller view or changes the source hierarchy.
BOOL SGRDynamicBarViewVisible(UIView *view);
uint32_t SGRDynamicBarContentBlockers(UIViewController *root);
UIScrollView *SGRDynamicBarScrollOwner(UIViewController *controller);
