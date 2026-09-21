# Experimental dynamic bottom bar

Implements the presentation experiment for [issue #60](https://github.com/skopevoj/spoti.pw/issues/60).
The implementation is off by default and is not ready for a default-on release. It requires the
Redesigned look and iOS 26+. Enable **Player → Now playing → Dynamic bottom bar**, then restart.

## Architecture

Spotify continues to own the playback state, controls, gestures, decoder, controller hierarchy and
navigation actions. The feature does not reconstruct Now Playing from the shared metadata cache.

- `DynamicBarCoordinator` owns one presentation session per window. Existing player/tab-bar hooks
  refresh it after Spotify's layouts; coalesced scroll attachment/content-size events also refresh
  feeds that become ready asynchronously. No scroll delegate or per-offset observer is replaced. It releases its host before snapshot setup and when content,
  visibility, accessibility or keyboard state makes compact presentation unsuitable.
- `DynamicBarCapabilities` inspects existing, loaded controllers/views without loading more views.
  It requires visible audio identities, or a known video controller with its live surface and track
  information inside the same stock card. Unknown video, attachment, Jam badge and hat identities fall back. It finds a single dominant vertical scroll view on the selected page; ambiguous
  layouts fail closed. Audio and video identities were captured on 9.1.78/iOS 27; video layout and lifecycle
  integration still need device verification. Class identity checks handle
  Swift runtime/display naming without equating mangled binary names with `NSStringFromClass`.
- `DynamicBarPolicy` rejects unsuitable width, height and interruption states without UIKit.
- `DynamicBarHost` is an added child with a real `UITabBarController`, presentation-only child
  controllers, and a `UITabAccessory`. Real page/player controllers remain in their original parents.
  Native selection is forwarded to the original tab sources, and its accepted selection is mirrored
  back. Home's long press uses the existing Mod Settings action.
- `DynamicBarScrollDriver` observes the existing pan recognizer without replacing its delegate.
  An upward drag expands through the public `.never` behavior inside a spring animation; the end of the gesture restores
  `.onScrollDown` before the next gesture begins. This was needed for repeatable cycles in the probe.
- `LiveBarLayout` leases the original player's layout. `LiveBarConstraints` recognizes the captured
  9.1.78 audio profile: four root edge pins, 56-point root/card heights, and artwork with 8-point
  vertical padding. It temporarily replaces root placement constraints and adjusts card height and
  padding, retaining the 40-point artwork/control row and the original enclosing bar height. Other frame-based layouts use bounds/center. It checks
  ancestor transforms/clipping, the actual card's post-layout frame, and control containment. It
  never reparents, scales or snapshots the player. Restoration only rewrites properties still owned
  by the lease. Spotify reclaiming the geometry suspends the adapter rather than causing a layout
  contest on every pass.
- The video adapter preserves the same `SPTVideoSurfaceImpl`, its layer and its parent. The captured
  surface aspect constraint remains untouched; the existing graph resizes video when card height changes. Audio/video
  attachment, detachment and rectangle callbacks release the lease before Spotify handles the change,
  then refresh after a natural layout pass. Nested callbacks hold separate suspension tokens. The
  [video fixture](../harness/dynamic-tabbar/fixtures/spotify-9.1.78-video.md) records the deeper
  device capture and the r6 profile rejection that led to this constraint model.

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
| Ordinary audio | Attempts native compact hosting only when positive identities and measured layout fit. User confirmed collapse/expand on physical r5; upward animation was abrupt and is corrected in the next candidate. |
| Captured live video profile | Candidate preserves the original surface and aspect through compact hosting. Real playback and audio/video switches await device validation. |
| Unknown video, Jam badge, attachments, extra hat content | Restores the existing expanded bars when detected. |
| Unknown hierarchy, fixed/non-fitting card, clipping/transformed ancestor | Keeps the existing presentation; no guessed selectors or edits to unrecognized constraint profiles. |
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

Verified revision: `8c131eadd122353e14687e3e13ab0d59f9ea8393` (r6), 2026-09-21. Private run
`35550153517` completed with **64 passed, 0 failed, 0 skipped**, and built the full diagnostic IPA
from the same commit. This includes the upstream main merge already present in the user fork. The previous r4 52-test result is historical and did not pass physical
acceptance; see the device findings below.

| Check | Result |
| --- | --- |
| Live layout lease and fitting | 25 UIKit unit tests passed, including the measured constraint graph, restoration and RTL |
| Content and scroll capability inspection | 21 UIKit unit tests passed, including the captured ElementView audio identities |
| Coordinator interruption, readiness, restoration and read-only diagnostics | 14 UIKit unit tests passed |
| Native-owned, externally-owned, constrained audio and video scrolling | 4 UI tests passed; each performs 3 collapse/expand cycles, presses the original button each cycle and selects Library |
| Pure fitting/interruption policy | Passed locally with AddressSanitizer and UndefinedBehaviorSanitizer |
| Layer boundaries and patch whitespace | Passed |
| Full Theos compile, package and IPA injection | Passed with the private Spotify 9.1.78 input |
| Physical Spotify runtime | User confirmed audio collapse/expand in r5. Expansion animation was abrupt; video fell back as designed and is now an explicit support requirement. New candidate awaits installation and physical verification. |

The test command uses `pipefail`; its outcome and the exported individual test counts were checked
separately. The final source revision is recorded so documentation-only follow-ups are not mistaken
for a newly tested binary. The earlier 34-test build missed the real ordinary-audio structure, as described below.

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
card sizing and control overflow. The replacement r2 build (`6010c41`, run `35525643670`) passed 40 tests including this correction, separately from the initial
34-test build. The user retested r2 after installation and reported no collapse. A 56-point stock card fitting
the shorter accessory remains an open integration question.

Required before proposing default enablement: capture sanitized audio/video/Jam structures; verify
ordinary audio and all playback actions; test video/audio switches without track changes; verify
full-player open/dismiss/cancel, Connect, no-item/stop, navigation variants, accessibility, keyboard,
background/foreground, rotation and banners. Check the diagnostic `dynamic bar: presentation blockers`
bitmask against `DynamicBarPolicy.h` when the adapter declines to attach. Logs contain presentation
reasons, not track titles or account information. Disable the setting and restart to roll back.

Diagnostic revision r3 (`a3215b1`, historical run `35526406897`, 41 passed) adds a read-only section to the existing debug USB tree endpoint. It
preserves the last placement rejection, reports current visibility and scroll ownership, and lists
layout constraints without label text. This avoids depending on transient syslog messages across
process replacement. It is diagnostic work, not evidence that the remaining integration failure
is fixed. On 2026-09-21 r3 was installed and its read-only endpoint showed two failures:

- Home became scrollable after the last bar layout, leaving cached blockers `0x810` despite an
  eligible live tree. Switching tabs refreshed eligibility.
- Placement then failed with an actual card of 386×56 in a native slot of 360×48. Root bounds
  alone could not resize the Auto Layout card. The captured constraints are documented in the fixture.

The next revision adds the narrow constraint lease and event-driven readiness refresh above.
Regression coverage includes a captured constraint fixture, repeated width changes, restoration,
foreign updates, reparenting, RTL, late Home population, scroll removal and unrelated scroll events.
A third UI scenario exercises that constrained player through the real native accessory and scroll
recognizer. All 52 tests passed in r4 follow-up run `35548171834` (`b7b8941`). Its production sources
were identical to the r4 IPA build (`b119fda`, run `35547829963`). The first 52-test attempt passed all three
UI scenarios but failed a unit hit test that supplied a UIWindow instead of the production host
view coordinate space. That assertion was corrected and rerun without changing the installed code.
r4 was installed successfully, but the device still fell back. The new report showed the correct
360×48 card size at y=-332.5 relative to its slot. The original source height/pins also supplied
the enclosing Auto Layout bar's height; releasing them removed that sizing contribution. The next
revision holds the original parent height during the lease, and tests both ambiguous layout and
window position with a parent sized by its child instead of a fixed-frame parent. The user confirmed r5 now collapses on downward scrolling and expands on upward scrolling.
The upward transition jumped to its endpoint, and video still used the deliberate fallback.
Both are being addressed in the next candidate; the broader device matrix remains outstanding.

### Expansion and live video follow-up

Expansion revision `a5891b6`, private run `35549346705`, passed all 53 tests. The constrained UI
scenario now requires at least two moving intermediate presentation-layer frames aligned with the
real native accessory within 3 points, on each of three expansion cycles. This is simulator evidence,
not yet a physical result.

The video candidate adds landscape/portrait aspect fixtures, surface/layer/parent identity checks,
external dimension replacement and surface detachment, positive video eligibility, nested lifecycle
suspension, and a fourth native gesture UI scenario. All 64 tests passed in the r6 run above; real video playback and audio/video switching still need
physical verification. The fixture uses a generic colored view, not an actual decoder.

### r6 physical video diagnosis

r6 reached the physical iPhone and supplied the deeper read-only tree while video played on Home.
The classifier admitted video (`content-blockers=0`), but the adapter rejected its constraint profile
(`host=0`, `failed-placement=1`). The actual required aspect constraint belongs to the live surface,
not the enclosing video controller view. r7 replaces the inferred dimension fixture with that
captured ownership and preserves the surface's aspect constraint unchanged. r7 validation is pending.
