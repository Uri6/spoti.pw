// What the harness does not compile: the accent hook (SGRAccent.x), the repaint hook (SGRRepaint.x), the
// tab bar's composition (Navbar.x) and Mod Settings. Spotify's order of tabs stays as the mock has it.
#import <UIKit/UIKit.h>
#import "Redesigned/Navbar/DynamicBarCoordinator.h"

UIColor *SGRAccentColor(void) { return nil; }
__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_nowPlayingCard = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

void SGRComposeTabBar(UIView *tabBar) {}
void SGRLogTabBarRow(UIView *tabBar) {}
void SGOpenModSettings(UIView *source) {}

// This legacy harness covers the existing expanded bars. Dynamic hosting has its own UIKit probe.
void SGRDynamicBarUpdateTabs(UIViewController *container, UIView *stockBar, UITabBar *mirror,
                            NSArray<UIView *> *sources, void (^select)(UIView *)) {}
void SGRDynamicBarUpdatePlayer(UIViewController *container, UIView *card, UIVisualEffectView *glass) {}
