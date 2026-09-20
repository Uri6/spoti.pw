#import "DynamicBarCapabilities.h"
#import "../../Core/SGViewTree.h"
#import <objc/runtime.h>

BOOL SGRDynamicBarViewVisible(UIView *view) {
    if (!view.window || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *v = view; v; v = v.superview) if (v.hidden || v.alpha < 0.01) return NO;
    return YES;
}

// Swift's runtime name and NSStringFromClass are not interchangeable. Resolve the actual class,
// including subclasses, instead of comparing a demangled display name to a mangled binary name.
static BOOL hasIdentity(id object, const char *runtimeName, NSString *displayName) {
    Class type = objc_lookUpClass(runtimeName);
    if (type && [object isKindOfClass:type]) return YES;
    type = displayName ? NSClassFromString(displayName) : Nil;
    return type && [object isKindOfClass:type];
}

// The 9.1.78 device capture contains Content + ElementView artwork/track info, with no
// BarCoverArtViewController child. Keep the older cover-controller shape as a separate capability.
// Do not use playback-URI heuristics: video/Jam can change without a new URI.
uint32_t SGRDynamicBarContentBlockers(UIViewController *root) {
    if (!root) return SGRDynamicBarUnknownContent;
    BOOL cover = NO, content = NO;
    uint32_t reasons = 0;
    NSMutableArray<UIViewController *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        UIViewController *vc = pending.lastObject;
        [pending removeLastObject];
        if (!SGRDynamicBarViewVisible(vc.viewIfLoaded)) continue;
        NSString *name = NSStringFromClass(vc.class);
        cover |= hasIdentity(vc, "_TtC18NowPlaying_BarImpl25BarCoverArtViewController", @"NowPlaying_BarImpl.BarCoverArtViewController");
        content |= hasIdentity(vc, "_TtC18NowPlaying_BarImpl35ContentViewControllerImplementation", @"NowPlaying_BarImpl.ContentViewControllerImplementation");
        if (hasIdentity(vc, "_TtC18NowPlaying_BarImpl22BarVideoViewController", @"NowPlaying_BarImpl.BarVideoViewController")) reasons |= SGRDynamicBarVideo;
        if ([name containsString:@"AttachmentController"]) reasons |= SGRDynamicBarExtraContent;
        [pending addObjectsFromArray:vc.childViewControllers];
    }
    __block BOOL extra = NO, elementAudio = NO;
    SGForEachView(root.viewIfLoaded, ^(UIView *view) {
        if (!SGRDynamicBarViewVisible(view)) return;
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"JamListeningAlongLiveBadge"] || [name containsString:@"NowPlayingBarHatElementUI"] ||
            hasIdentity(view, "_TtC18NowPlaying_BarImpl14AttachmentView", @"NowPlaying_BarImpl.AttachmentView")) extra = YES;
        if (![view.accessibilityIdentifier isEqualToString:@"SPTNowPlayingBar"]) return;
        // Both positive elements must be visible in this same stock card. An arbitrary image,
        // label, or stale element on another page must not make an unknown card eligible.
        __block BOOL artwork = NO, trackInfo = NO;
        SGForEachView(view, ^(UIView *child) {
            if (!SGRDynamicBarViewVisible(child)) return;
            artwork |= hasIdentity(child, "_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__", nil);
            trackInfo |= hasIdentity(child, "_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI24BarTrackInfoElementPropsP_P__", nil);
        });
        elementAudio |= artwork && trackInfo;
    });
    if (!content || (!cover && !elementAudio)) reasons |= SGRDynamicBarUnknownContent;
    return reasons | (extra ? SGRDynamicBarExtraContent : 0);
}

// Only a single, dominant vertical list on the active page is eligible. Carousels, the full player,
// ambiguous nested lists, and sheets never become implicit global scroll owners.
UIScrollView *SGRDynamicBarScrollOwner(UIViewController *controller) {
    if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).visibleViewController;
    UIView *page = controller.viewIfLoaded;
    if (!SGRDynamicBarViewVisible(page) || controller.presentedViewController) return nil;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController) {
        if (parent.transitionCoordinator || parent.presentedViewController) return nil;
    }
    __block UIScrollView *best = nil;
    __block CGFloat bestArea = 0;
    __block BOOL ambiguous = NO;
    SGForEachView(page, ^(UIView *view) {
        if (![view isKindOfClass:UIScrollView.class] || !SGRDynamicBarViewVisible(view)) return;
        UIScrollView *scroll = (UIScrollView *)view;
        if (!scroll.scrollEnabled || scroll.bounds.size.width < page.bounds.size.width * 0.65 ||
            scroll.bounds.size.height < page.bounds.size.height * 0.45 ||
            scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom <= scroll.bounds.size.height + 32 ||
            [scroll.accessibilityIdentifier isEqualToString:@"scrolling_npv_collection_view_accessibility_identifier"]) return;
        CGFloat area = scroll.bounds.size.width * scroll.bounds.size.height;
        if (area > bestArea * 1.1) { best = scroll; bestArea = area; ambiguous = NO; }
        else if (area >= bestArea * 0.9) ambiguous = YES;
    });
    return ambiguous ? nil : best;
}
