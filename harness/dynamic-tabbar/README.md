# Native tab accessory feasibility probe

This standalone app compares public UIKit minimization with an owned scroll view against an external
scroll view designated by `setContentScrollView:forEdge:`. Both use the production scroll driver.
In the external case, the production chrome host positions the original player view while keeping
its original controller and view parents. Its hit-test bridge delivers touches to the original
button. A third `constrained` scenario uses the root/card/artwork constraint graph captured from
Spotify 9.1.78 and the production constraint lease through the same native accessory. The `video` scenario adds a synthetic live-surface layout with the captured nesting and guarded
fixed dimensions described in the video fixture. No Spotify binary or private UIKit selectors are involved.

The UI tests send actual drag gestures, assert the accessory's inline/regular trait, test its action
while inline, repeat three cycles, select a different tab, and retain screenshots. The external
button receives a real screen-coordinate touch: XCTest's accessibility hittability clips it at
its original parent's bounds. This is an accessibility limitation, not a mocked button action.
Production opts out for VoiceOver, Switch Control, AssistiveTouch, Reduce Motion and accessibility
text sizes. Voice Control and other accessibility interactions still require device validation.

Hosted unit tests exercise the production layout lease, content/scroll classifiers and presentation
coordinator. The [ordinary-audio fixture](fixtures/spotify-9.1.78-audio.md) reproduces identities and
nesting observed on a physical device; the constrained fixture also reproduces its measured
layout relationships with synthetic content. It does not reproduce every private Spotify subview. Other controller names
correspond to binary metadata. The fixtures cover positive video admission, unknown-video/extra-content rejection, ambiguous/short/horizontal
scroll views, geometry replacement, fixed cards, restoration, keyboard, player appearance and
transition setup before the animator supplies its bar, late feed population, constraint restoration,
external height changes, reparenting and right-to-left geometry. Video tests retain the same surface,
parent and layer across 4:3, 16:9 and 9:16 layouts, and cover nested media callbacks. The two
constrained UI scenarios also require multiple aligned presentation-layer frames during expansion.

Generate with `xcodegen generate --spec project.yml`, then run the `DynamicTabBarProbe` test scheme on
an iOS 26+ simulator. The private development workflow selects an available runtime and saves results.

Run the UIKit-free fitting policy from the repository root:

```sh
clang -x c -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  harness/dynamic-tabbar/policy-test.c tweak/Sources/Redesigned/Navbar/DynamicBarPolicy.m \
  -o /tmp/spoti-dynamic-policy-test
/tmp/spoti-dynamic-policy-test
```

A pass proves only that UIKit can observe scrolling in this topology on the tested runtime. It does
not prove Spotify's containment, live video, Jam, safe-area updates, or full-player transitions work.
Those need independent real-app evidence before the feature is enabled.
