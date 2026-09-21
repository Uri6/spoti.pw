#import "Core/SGCore.h"
#import "DynamicBarCoordinator.h"

%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    SGRDynamicBarScrollChanged(self);
}
- (void)setContentSize:(CGSize)size {
    CGSize previous = self.contentSize;
    %orig;
    if (!CGSizeEqualToSize(previous, self.contentSize)) SGRDynamicBarScrollChanged(self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGHidden(SGRKeyDynamicBar)) return;
    %init;
}
