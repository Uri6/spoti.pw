# Experimental dynamic bottom bar

Implements the presentation experiment for [issue #60](https://github.com/skopevoj/spoti.pw/issues/60).
The implementation is off by default and is not ready for a default-on release. It requires the
Redesigned look and iOS 26+. Enable **Player → Now playing → Dynamic bottom bar**, then restart.

## Architecture

Spotify continues to own the playback state, controls, gestures, decoder, controller hierarchy and
navigation actions. The feature does not reconstruct Now Playing from the shared metadata cache.

- `DynamicBarCoordinator` owns one presentation session per window. Existing player/tab-bar hooks
  refresh it after Spotify's layouts. It releases its host before snapshot setup and when content,
  visibility, accessibility or keyboard state makes compact presentation unsuitable.
- `DynamicBarCapabilities` inspects existing, loaded controllers/views without loading more views.
  It requires visible audio identities and rejects observed video, attachment, Jam badge and hat
  identities. It finds a single dominant vertical scroll view on the selected page; ambiguous
  layouts fail closed. Ordinary-audio identities were captured on 9.1.78/iOS 27; video/extra-content
  co-occurrence and lifecycle timing remain to be verified on a device. Class identity checks handle
  Swift runtime/display naming without equating mangled binary names with `NSStringFromClass`.
- `DynamicBarPolicy` rejects unsuitable width, height and interruption states without UIKit.
- `DynamicBarHost` is an added child with a real `UITabBarController`, presentation-only child
  controllers, and a `UITabAccessory`. Real page/player controllers remain in their original parents.
  Native selection is forwarded to the original tab sources, and its accepted selection is mirrored
  back. Home's long press uses the existing Mod Settings action.
- `DynamicBarScrollDriver` observes the existing pan recognizer without replacing its delegate.
  An upward drag expands through the public `.never` behavior; the end of the gesture restores
  `.onScrollDown` before the next gesture begins. This was needed for repeatable cycles in the probe.
- `LiveBarLayout` temporarily changes only the original player's root bounds and center. It checks
  ancestor transforms/clipping, the actual card's post-layout frame, and control containment. It
  never reparents, scales or snapshots the player. Restoration only rewrites properties still owned
  by the lease. Spotify reclaiming the geometry suspends the adapter rather than causing a layout
  contest on every pass.

The native accessory supplies the glass and geometry. A passthrough host returns the original
control from hit testing, including when its card extends outside its original parent's bounds.
Player artwork, title, progress and actions stay live. Styling runs during placement and restoration,
with a recursion guard, so a subsequent full-player snapshot sees restored geometry.

## Apple APIs

The public UIKit APIs are `UITabBarController.tabBarMinimizeBehavior`, `UITabAccessory` through
`bottomAccessory`, `UITraitCollection.tabAccessoryEnvironment`, and
`UIViewController.setContentScrollView(_:for:)`. See [Apple's UIKit demonstration](https://developer.apple.com/videos/play/wwdc2025/284/)
and [content scroll-view documentation](https://developer.apple.com/documentation/uikit/uiviewcontroller/setcontentscrollview(_:for:)).
A standalone `UITabBar` cannot provide this behavior by itself.

Accessibility fallback observes Apple's documented status notifications and capabilities in
[UIAccessibility](https://developer.apple.com/documentation/uikit/uiaccessibility).

## Deliberate fallback and remaining limits

| Case | Current behavior / limit |
| --- | --- |
| Ordinary audio | Attempts native compact hosting only when positive identities and measured layout fit. Its real controller/element identities were captured; live compact layout is not yet validated. |
| Video, Jam badge, attachments, extra hat content | Restores the existing expanded bars when detected. Detection tested with synthetic trees, not real sessions. |
| Unknown hierarchy, fixed/non-fitting card, clipping/transformed ancestor | Keeps the existing presentation; no guessed selectors or forced resizing of child constraints. |
| Keyboard, full player, transition, inactive app, hidden stock bar | Suspends presentation and restores owned geometry. Actual Spotify transition/cancellation timing remains unverified. |
| Regular width, narrow layout, large accessibility text, VoiceOver, Switch Control, AssistiveTouch, Reduce Motion | Expanded fallback. |
| Touch outside the original parent | Screen touches worked in the UIKit probe. XCTest AX hittability does not follow that out-of-parent geometry; accessibility support cannot be claimed for the compact view. |
| Voice Control / other assistive technologies | Not validated; automatic detection/fallback is not claimed. |
| Safe areas / last page row / Offline and Private Session banners | Existing page insets are retained. This version does **not** reclaim the freed vertical space when compact. Device checks must confirm banner alignment and no obscured content. |
| Podcasts, audiobooks, Connect/AirPlay, ads, Canvas | Keeps original behavior and applies the same measured guards. Variant-specific compact support and transitions remain unverified. |
| iPad, landscape, RTL, reordered/hidden/custom tabs, deep links | Some are guarded or inherit existing actions, but the real-app matrix is outstanding. |
| Future Spotify versions | Unknown identities/layouts fall back; classifier and hook compatibility need revalidation. |

## Validation and reproduction

See [the harness](../harness/dynamic-tabbar/README.md). CI uses Xcode 26.6 with an iPhone Air simulator
running iOS 26.5, builds the production files into a standalone UIKit app, exports `.xcresult`
summaries/attachments, and preserves the test command's exit status. Full Theos builds also inject
the result into the privately supplied Spotify 9.1.78 IPA; the app binary and recordings stay out of
the public repository.

Verified code revision: `a85333b5bb8c03dcfea45b8c50fc6a57c3d7d23a`, 2026-09-20. The private development
run `35523040471` completed successfully with **34 passed, 0 failed, 0 skipped** tests:

| Check | Result |
| --- | --- |
| Live layout lease and fitting | 13 UIKit unit tests passed |
| Content and scroll capability inspection | 12 UIKit unit tests passed |
| Coordinator interruption and restoration | 7 UIKit unit tests passed |
| Native-owned and externally-owned scrolling | 2 UI tests passed; each performs 3 collapse/expand cycles, presses the original button each cycle and selects Library |
| Pure fitting/interruption policy | Passed locally with AddressSanitizer and UndefinedBehaviorSanitizer |
| Layer boundaries and patch whitespace | Passed |
| Full Theos compile, package and IPA injection | Passed with the private Spotify 9.1.78 input |
| Physical Spotify runtime | Installed on iOS 27. User recording shows the bars do not collapse with the option enabled; integration is not passing. |

The test command uses `pipefail`; its outcome and the exported individual test counts were checked
separately. The final source revision is recorded so documentation-only follow-ups are not mistaken
for a newly tested binary. The previous code revision also passed its 32-test suite.

The approved [design and device matrix](superpowers/specs/2026-09-20-dynamic-navbar-design.md) remain
the acceptance criteria. A passing UIKit fixture or successful IPA build is not a completed
real-Spotify integration test.

### Device regression after the first build

The 2026-09-20 screen recording showed an unchanged expanded bar while scrolling. A subsequent USB
capture confirmed `spotifyglass.redesign.navbar.dynamic = 1`. The captured audio hierarchy contains
`ContentViewControllerImplementation` and `ElementView` artwork/track information, but **no**
`BarCoverArtViewController`. The initial classifier required that missing controller and therefore
could not admit this real layout, despite the synthetic tests passing.

The correction recognizes both positive elements inside the same `SPTNowPlayingBar` card, keeps
video/Jam/attachment rejection, and resolves Swift class identities instead of comparing display
names against mangled names. Regression fixtures reproduce the captured audio identities and a
hidden Jam badge. Layout rejection diagnostics now distinguish clipping, reclaimed geometry,
card sizing and control overflow. The initial 34-test result above predates this correction;
its replacement build and device behavior must be checked separately. A 56-point stock card fitting
the shorter accessory remains an open integration question.

Required before proposing default enablement: capture sanitized audio/video/Jam structures; verify
ordinary audio and all playback actions; test video/audio switches without track changes; verify
full-player open/dismiss/cancel, Connect, no-item/stop, navigation variants, accessibility, keyboard,
background/foreground, rotation and banners. Check the diagnostic `dynamic bar: presentation blockers`
bitmask against `DynamicBarPolicy.h` when the adapter declines to attach. Logs contain presentation
reasons, not track titles or account information. Disable the setting and restart to roll back.
