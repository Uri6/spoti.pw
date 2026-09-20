// The Now playing page of the redesign, under Player (App/Pages.m puts it there).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"
#import "Redesigned/Navbar/DynamicBarCoordinator.h"

UIViewController *SGRNowPlayingBarSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Now playing" intro:SGRestartNote sections:@[
        SGSection(nil, @[
            SGUnstableRow(@"Dynamic bottom bar", @"Move Now Playing into the tab row while scrolling", SGRKeyDynamicBar,
                @"Experimental. Verified audio layouts can collapse; video, extra content and unsupported layouts stay expanded. Device validation is still in progress."),
            SGHideRow(@"Hide the device button", @"The speaker icon on the now playing bar", SGRHideBarConnect),
        ]),
    ] footer:nil];
}
