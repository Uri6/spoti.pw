# Native tab accessory feasibility probe

This standalone app compares public UIKit minimization with an owned scroll view against an external
scroll view explicitly designated by `setContentScrollView:forEdge:`. In the external case, the page
and overlay tab controller are sibling child controllers. A passthrough host preserves touches to
the page. No Spotify code or private UIKit selectors are involved.

The UI tests send actual drag gestures, assert the accessory's inline/regular trait, test its action
while inline, and retain screenshots. Programmatically setting a content offset is not a substitute.

Generate with `xcodegen generate --spec project.yml`, then run the `DynamicTabBarProbe` test scheme on
an iOS 26+ simulator. The private development workflow selects an available runtime and saves results.

A pass proves only that UIKit can observe scrolling in this topology on the tested runtime. It does
not prove Spotify's containment, live video, Jam, safe-area updates, or full-player transitions work.
Those need independent real-app evidence before the feature is enabled.
