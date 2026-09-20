// Public-API feasibility probe, not a mock of Spotify's player or proof of Spotify integration.
#import <UIKit/UIKit.h>

@interface ProbeAccessory : UIView
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *play;
@property(nonatomic) NSUInteger presses;
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
    self.status.accessibilityValue = inlineMode ? @"inline" : @"regular";
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

@interface ProbeRoot : UIViewController
@property(nonatomic, strong) UITabBarController *tabs;
@property(nonatomic, strong) ProbePage *page;
@end
@implementation ProbeRoot
- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL external = [NSProcessInfo.processInfo.arguments containsObject:@"external"];
    self.page = [ProbePage new];
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
    if (external) {
        [self addChildViewController:self.page];
        self.page.view.frame = self.view.bounds;
        self.page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:self.page.view];
        [self.page didMoveToParentViewController:self];
        for (UIViewController *page in pages) [page setContentScrollView:self.page.tableView forEdge:NSDirectionalRectEdgeBottom];
    }
    [self addChildViewController:self.tabs];
    UIView *host = external ? [ProbePassthrough new] : [UIView new];
    host.frame = self.view.bounds;
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:host];
    self.tabs.view.frame = host.bounds;
    self.tabs.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tabs.view.backgroundColor = UIColor.clearColor;
    [host addSubview:self.tabs.view];
    [self.tabs didMoveToParentViewController:self];
    if (external) {
        ((ProbePassthrough *)host).bar = self.tabs.tabBar;
        ((ProbePassthrough *)host).accessory = accessory;
    }
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
