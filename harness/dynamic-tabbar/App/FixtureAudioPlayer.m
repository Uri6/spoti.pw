#import "FixtureAudioPlayer.h"
#import <objc/runtime.h>

static UIView *addView(UIView *parent) {
    UIView *view = [UIView new];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:view];
    return view;
}
static NSArray *pins(UIView *view, UIView *parent) {
    return @[[view.topAnchor constraintEqualToAnchor:parent.topAnchor],
             [view.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
             [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
             [view.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor]];
}
@implementation FixtureAudioPlayer {
    NSUInteger _presses;
}
- (instancetype)initInParent:(UIView *)parent {
    if (!(self = [super init])) return nil;
    _source = addView(parent);
    _rootPins = pins(_source, parent);
    [NSLayoutConstraint activateConstraints:_rootPins];
    [_source.heightAnchor constraintEqualToConstant:56].active = YES;
    UIView *bar = addView(_source);
    [NSLayoutConstraint activateConstraints:@[[bar.topAnchor constraintEqualToAnchor:_source.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:_source.bottomAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:_source.leadingAnchor constant:8],
        [_source.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:8]]];
    _card = addView(bar);
    _card.accessibilityIdentifier = @"SPTNowPlayingBar";
    _card.clipsToBounds = YES;
    _cardHeight = [_card.heightAnchor constraintEqualToConstant:56];
    [NSLayoutConstraint activateConstraints:@[_cardHeight,
        [_card.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],
        [_card.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
        [_card.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor]]];
    UIView *content = addView(_card);
    content.accessibilityIdentifier = @"now-playing-bar-content";
    [NSLayoutConstraint activateConstraints:pins(content, _card)];
    UIView *artWrapper = addView(content);
    _artwork = addView(artWrapper);
    [NSLayoutConstraint activateConstraints:pins(_artwork, artWrapper)];
    _artTop = [_artwork.topAnchor constraintEqualToAnchor:content.topAnchor constant:8];
    NSLayoutConstraint *square = [_artwork.widthAnchor constraintEqualToAnchor:_artwork.heightAnchor];
    square.priority = 999;
    [NSLayoutConstraint activateConstraints:@[_artTop, square,
        [content.bottomAnchor constraintEqualToAnchor:_artwork.bottomAnchor constant:8],
        [_artwork.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8]]];
    const char *name = "_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__";
    Class cls = objc_lookUpClass(name);
    if (!cls) { cls = objc_allocateClassPair(UIView.class, name, 0); objc_registerClassPair(cls); }
    UIView *image = [cls new];
    image.translatesAutoresizingMaskIntoConstraints = NO;
    [_artwork addSubview:image];
    [NSLayoutConstraint activateConstraints:pins(image, _artwork)];
    image.backgroundColor = UIColor.systemIndigoColor;
    _status = [UILabel new];
    _status.text = @"Now Playing";
    _status.accessibilityIdentifier = @"accessory.environment";
    _status.accessibilityValue = @"regular";
    [_status setContentCompressionResistancePriority:749 forAxis:UILayoutConstraintAxisHorizontal];
    _play = [UIButton buttonWithType:UIButtonTypeSystem];
    [_play setTitle:@"Play" forState:UIControlStateNormal];
    _play.accessibilityIdentifier = @"accessory.play";
    [_play addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside];
    [_play.widthAnchor constraintEqualToConstant:44].active = YES;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_status, _play]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:_artwork.trailingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [row.topAnchor constraintEqualToAnchor:_artwork.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:_artwork.bottomAnchor],
        [row.centerYAnchor constraintEqualToAnchor:content.centerYAnchor]]];
    [parent layoutIfNeeded];
    return self;
}
- (void)pressed {
    self.play.accessibilityValue = [NSString stringWithFormat:@"%lu", (unsigned long)++_presses];
}
@end
