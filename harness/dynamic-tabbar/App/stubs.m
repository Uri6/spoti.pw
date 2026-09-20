#import <UIKit/UIKit.h>

// Standalone app configuration only. The production coordinator and its adapters are unmodified.
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGHidden(NSString *key) { return [key isEqualToString:@"spotifyglass.redesign.navbar.dynamic"]; }
void SGOpenModSettings(UIView *source) {}
