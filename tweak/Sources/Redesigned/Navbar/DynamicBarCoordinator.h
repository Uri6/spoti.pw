#import <UIKit/UIKit.h>

#define SGRKeyDynamicBar @"spotifyglass.redesign.navbar.dynamic"

// Existing bar hooks call these after Spotify's own layout. Disabled unless explicitly requested
// at launch; all ownership is scoped to the source window.
void SGRDynamicBarUpdateTabs(UIViewController *container, UIView *stockBar, UITabBar *mirror,
                             NSArray<UIView *> *sources, void (^select)(UIView *source));
void SGRDynamicBarUpdatePlayer(UIViewController *container, UIView *card, UIVisualEffectView *glass);
// Called only for scroll attachment and content-size changes, never per-scroll offset.
void SGRDynamicBarScrollChanged(UIScrollView *scroll);
// Release leased geometry before Spotify changes a live video surface or its dimensions.
// The token holds suspension through nested callbacks and the next natural layout pass.
id SGRDynamicBarBeginMediaChange(UIViewController *controller);
void SGRDynamicBarEndMediaChange(id token);
void SGRDynamicBarBeginTransition(UIView *bar, id transition);
void SGRDynamicBarEndTransition(id transition);
void SGRDynamicBarPlayerVisibility(UIViewController *player, BOOL visible);
