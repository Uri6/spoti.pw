// Public-API feasibility probe, not a mock of Spotify's player or proof of Spotify integration.
#import <UIKit/UIKit.h>
#import "FixtureAudioPlayer.h"
#import "ProbeExpansionMotion.h"
#import "../../../tweak/Sources/Redesigned/Navbar/DynamicBarScrollDriver.h"
#import "../../../tweak/Sources/Redesigned/Navbar/DynamicBarHost.h"
#import "../../../tweak/Sources/Redesigned/NowPlayingBar/LiveBarLayout.h"

@interface ProbeAccessory : UIView
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *play;
@property(nonatomic) NSUInteger presses;
@property(nonatomic, copy) NSString *externalEnvironment;
@end
@implementation ProbeAccessory
- (instancetype)init {
    if ((self = [super init])) {
        self.accessibilityIdentifier = @"accessory";
        _status = [UILabel new];
        _status.text = @"Now Playing";
        _status.textColor = UIColor.labelColor;
        _status.accessibilityIdentifier = @"accessory.environment";
        [self addSubview:_status];
        _play = [UIButton buttonWithType:UIButtonTypeSystem];
        [_play setTitle:@"Play" forState:UIControlStateNormal];
        _play.accessibilityIdentifier = @"accessory.play";
        [_play addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_play];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 56); }
- (void)pressed {
    self.presses++;
    self.play.accessibilityValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.presses];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL inlineMode = self.traitCollection.tabAccessoryEnvironment == UITabAccessoryEnvironmentInline;
    self.status.accessibilityValue = self.externalEnvironment ?: (inlineMode ? @"inline" : @"regular");
    self.status.frame = CGRectMake(12, 0, MAX(0, self.bounds.size.width - 80), self.bounds.size.height);
    self.play.frame = CGRectMake(self.bounds.size.width - 64, 0, 56, self.bounds.size.height);
    NSLog(@"PROBE accessory %@ frame %@", self.status.accessibilityValue, NSStringFromCGRect(self.frame));
}
@end

@interface ProbePage : UITableViewController
@end
@implementation ProbePage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.accessibilityIdentifier = @"browse.list";
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
}
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section { return 100; }
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [view dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
    cell.textLabel.text = [NSString stringWithFormat:@"Browse row %ld", (long)path.row];
    return cell;
}
@end

// A properly contained controller whose empty content does not steal touches from the real page.
// This deliberately does NOT reparent that page into UIKit's tab controller.
@interface ProbePassthrough : UIView
@property(nonatomic, weak) UITabBar *bar;
@property(nonatomic, weak) UIView *accessory;
@end
@implementation ProbePassthrough
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.bar || [hit isDescendantOfView:self.bar] ||
        hit == self.accessory || [hit isDescendantOfView:self.accessory]) return hit;
    return nil;
}
@end

@interface ProbeRoot : UIViewController <SGRDynamicBarHostDelegate>
@property(nonatomic, strong) UITabBarController *tabs;
@property(nonatomic, strong) ProbePage *page;
@property(nonatomic, strong) SGRDynamicBarScrollDriver *driver;
@property(nonatomic, strong) SGRDynamicBarHost *chrome;
@property(nonatomic, strong) UIViewController *originalPlayerParent;
@property(nonatomic, strong) UIViewController *originalPlayer;
@property(nonatomic, strong) ProbeAccessory *livePlayer;
@property(nonatomic, strong) FixtureAudioPlayer *constrainedPlayer;
@property(nonatomic, strong) ProbeExpansionMotion *motion;
@property(nonatomic, strong) SGRLiveBarLayout *liveLayout;
@property(nonatomic, copy) NSArray<UITabBarItem *> *items;
@end
@implementation ProbeRoot
- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL external = [NSProcessInfo.processInfo.arguments containsObject:@"external"] || [NSProcessInfo.processInfo.arguments containsObject:@"constrained"] || [NSProcessInfo.processInfo.arguments containsObject:@"video"];
    self.page = [ProbePage new];
    if (external) { [self installProjectedPlayer]; return; }
    self.tabs = [UITabBarController new];
    NSMutableArray<UIViewController *> *pages = [NSMutableArray array];
    for (NSString *title in @[@"Home", @"Library", @"Search"]) {
        UIViewController *page = !external && !pages.count ? self.page : [UIViewController new];
        page.view.backgroundColor = UIColor.clearColor;
        page.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
            image:[UIImage systemImageNamed:pages.count == 0 ? @"house" : pages.count == 1 ? @"books.vertical" : @"magnifyingglass"]
            tag:pages.count];
        [pages addObject:page];
    }
    self.tabs.viewControllers = pages;
    self.tabs.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
    ProbeAccessory *accessory = [ProbeAccessory new];
    self.tabs.bottomAccessory = [[UITabAccessory alloc] initWithContentView:accessory];
    self.driver = [SGRDynamicBarScrollDriver new];
    self.driver.tabController = self.tabs;
    self.driver.scrollView = self.page.tableView;
    self.driver.permitted = YES;
    [self addChildViewController:self.tabs];
    UIView *host = [UIView new];
    host.frame = self.view.bounds;
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:host];
    self.tabs.view.frame = host.bounds;
    self.tabs.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tabs.view.backgroundColor = UIColor.clearColor;
    [host addSubview:self.tabs.view];
    [self.tabs didMoveToParentViewController:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.motion invalidate];
}
- (void)installProjectedPlayer {
    [self addChildViewController:self.page];
    self.page.view.frame = self.view.bounds;
    self.page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.page.view];
    [self.page didMoveToParentViewController:self];

    self.chrome = [SGRDynamicBarHost new];
    self.chrome.delegate = self;
    [self addChildViewController:self.chrome];
    self.chrome.view.frame = self.view.bounds;
    self.chrome.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.chrome.view];
    [self.chrome didMoveToParentViewController:self];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *title in @[@"Home", @"Library", @"Search"]) {
        [items addObject:[[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:@"music.note"] tag:items.count]];
    }
    self.items = items;
    self.chrome.observedScrollView = self.page.tableView;
    [self.chrome setItems:items selectedIndex:0];
    self.chrome.permitsMinimization = YES;

    self.originalPlayerParent = [UIViewController new];
    self.originalPlayerParent.view = [ProbePassthrough new];
    [self addChildViewController:self.originalPlayerParent];
    self.originalPlayerParent.view.frame = CGRectMake(0, 100, self.view.bounds.size.width, 56);
    [self.view addSubview:self.originalPlayerParent.view];
    [self.originalPlayerParent didMoveToParentViewController:self];
    self.originalPlayer = [UIViewController new];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"constrained"] || [NSProcessInfo.processInfo.arguments containsObject:@"video"]) {
        [self.originalPlayerParent addChildViewController:self.originalPlayer];
        UIView *parent = self.originalPlayerParent.view;
        parent.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[[parent.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [parent.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [parent.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-91]]];
        self.constrainedPlayer = [[FixtureAudioPlayer alloc] initInParent:parent videoAspectRatio:[NSProcessInfo.processInfo.arguments containsObject:@"video"] ? 16.0/9 : 0];
        [self.view layoutIfNeeded];
        self.originalPlayer.view = self.constrainedPlayer.source;
        ((ProbePassthrough *)self.originalPlayerParent.view).accessory = self.constrainedPlayer.source;
        [self.originalPlayer didMoveToParentViewController:self.originalPlayerParent];
        self.motion = [[ProbeExpansionMotion alloc] initWithPlayer:self.constrainedPlayer.card accessory:self.chrome.tabController.bottomAccessory.contentView status:self.constrainedPlayer.status];
        return;
    }
    self.livePlayer = [ProbeAccessory new];
    self.livePlayer.externalEnvironment = @"regular";
    self.originalPlayer.view = self.livePlayer;
    [self.originalPlayerParent addChildViewController:self.originalPlayer];
    self.livePlayer.frame = self.originalPlayerParent.view.bounds;
    [self.originalPlayerParent.view addSubview:self.livePlayer];
    ((ProbePassthrough *)self.originalPlayerParent.view).accessory = self.livePlayer;
    [self.originalPlayer didMoveToParentViewController:self.originalPlayerParent];
}
- (void)dynamicBarHost:(SGRDynamicBarHost *)host accessoryRect:(CGRect)rect inView:(UIView *)view inline:(BOOL)inlineLayout {
    if (self.constrainedPlayer) {
        if (self.liveLayout.applying || !self.constrainedPlayer.source.window) return;
        if (!self.liveLayout) self.liveLayout = [[SGRLiveBarLayout alloc] initWithSource:self.constrainedPlayer.source cardView:self.constrainedPlayer.card];
        BOOL placed = [self.liveLayout placeCardInRect:rect ofView:view];
        BOOL sameOwner = self.originalPlayer.parentViewController == self.originalPlayerParent && self.constrainedPlayer.source.superview == self.originalPlayerParent.view;
        self.constrainedPlayer.status.accessibilityValue = placed && sameOwner ? (inlineLayout ? @"inline" : @"regular") : @"placement-failed";
        return;
    }
    if (!self.livePlayer.window) return;
    if (!self.liveLayout) self.liveLayout = [[SGRLiveBarLayout alloc] initWithSource:self.livePlayer cardView:self.livePlayer];
    self.livePlayer.externalEnvironment = inlineLayout ? @"inline" : @"regular";
    BOOL placed = [self.liveLayout placeCardInRect:rect ofView:view];
    BOOL sameOwner = self.originalPlayer.parentViewController == self.originalPlayerParent && self.livePlayer.superview == self.originalPlayerParent.view;
    self.livePlayer.status.accessibilityValue = placed && sameOwner ? self.livePlayer.externalEnvironment : @"placement-failed";
}
- (UIView *)dynamicBarHost:(SGRDynamicBarHost *)host hitTest:(CGPoint)point inView:(UIView *)view event:(UIEvent *)event {
    return [self.liveLayout hitTest:point fromView:view event:event];
}
- (void)dynamicBarHost:(SGRDynamicBarHost *)host didSelectIndex:(NSUInteger)index {
    dispatch_async(dispatch_get_main_queue(), ^{ [host setItems:self.items selectedIndex:index]; });
}
@end

@interface ProbeScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [ProbeRoot new];
    [self.window makeKeyAndVisible];
}
@end
@interface ProbeApp : UIResponder <UIApplicationDelegate>
@end
@implementation ProbeApp
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeApp.class)); }
}
