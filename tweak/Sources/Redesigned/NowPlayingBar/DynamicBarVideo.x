#import "Core/SGCore.h"
#import "Redesigned/Navbar/DynamicBarCoordinator.h"

// Class and all three void/object callbacks verified in Spotify 9.1.78 class metadata;
// the live BarVideoViewController + SPTVideoSurfaceImpl hierarchy is captured on device.
// Never replace/reparent the surface or access Swift ivars. Restore our dimension lease
// before Spotify handles attachment, detachment or a new video rectangle.
%hook _TtC18NowPlaying_BarImpl22BarVideoViewController
- (void)videoSurfaceDidAttachVideo:(id)surface {
    id token = SGRDynamicBarBeginMediaChange((UIViewController *)self);
    %orig;
    SGRDynamicBarEndMediaChange(token);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    id token = SGRDynamicBarBeginMediaChange((UIViewController *)self);
    %orig;
    SGRDynamicBarEndMediaChange(token);
}
- (void)videoSurfaceDidChangeVideoRect:(id)surface {
    id token = SGRDynamicBarBeginMediaChange((UIViewController *)self);
    %orig;
    SGRDynamicBarEndMediaChange(token);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGHidden(SGRKeyDynamicBar)) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl22BarVideoViewController"]);
}
