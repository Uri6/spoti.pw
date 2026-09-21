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
  layouts fail closed. Audio and video identities were captured on 9.1.78/iOS 27; the user confirmed video collapse in r9. Full audio/video lifecycle
  coverage still needs device verification. Class identity checks handle
  Swift runtime/display naming without equating mangled binary names with `NSStringFromClass`.
- `DynamicBarPolicy` rejects unsuitable width, height and interruption states without UIKit.
- `DynamicBarHost` is an added child with a real `UITabBarController`, presentation-only child
  controllers, and a `UITabAccessory`. Real page/player controllers remain in their original parents.
  Native selection is forwarded to the original tab sources, and its accepted selection is mirrored
  back. Home's long press uses the existing Mod Settings action.
- `DynamicBarScrollDriver` observes the existing pan recognizer without replacing its delegate.
  The r13 candidate expands via the public `.never` policy with a scoped animation compatibility
  boundary, and rearms `.onScrollDown` at gesture end for the next collapse.
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
A standalone `UITabBar` cannot provide this behavior by itself. The r13 candidate additionally
intercepts the public no-animation wrapper only during its own expansion policy write, as detailed
below. This compatibility behavior must be validated on each supported runtime.

Accessibility fallback observes Apple's documented status notifications and capabilities in
[UIAccessibility](https://developer.apple.com/documentation/uikit/uiaccessibility).

## Deliberate fallback and remaining limits

| Case | Current behavior / limit |
| --- | --- |
| Ordinary audio | Attempts native compact hosting only when positive identities and measured layout fit. User confirmed collapse on physical r5. Upward animation still jumped in r9/r10; r11 only expands automatically at the page top. r13 awaits physical validation. |
| Captured live video profile | The user confirmed live video collapse in r9. The original surface and aspect are preserved; the complete switching/lifecycle matrix remains outstanding. |
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

Latest completed full build and simulator validation: `0bc1dba3e5c67c6adfc22add0df9fbbb68448b7e`
(r13 base), 2026-09-21. Private run `35595905511` passed **72 tests, 0 failures, 0 skips** and
built the diagnostic IPA. All four UI scenarios passed their repeated collapse/expand, original
control-action and tab-selection checks; constrained audio and video also passed intermediate-frame
alignment checks. The earlier first r13 probe also passed 72 tests, while its full build caught
missing deployment-target availability guards; those were fixed before the successful full build.

The follow-up `59f353a24f6908abedca7ca92422899489fdf6ec` preserves expansion during repeated
eligibility refreshes and adds one regression. Its local compatibility compile, layer checks and
whitespace checks pass. Run `35596062235` **did not start either job**: GitHub reported failed recent
account payments or a spending-limit restriction. Its expected 73-test suite and complete IPA build
are therefore **not validated**. No billing settings were changed.

The physical iPhone remains on r11. Mirroring returned to its Touch ID lock after reconnecting, and
USB/network device discovery currently finds no phone. Neither r12 nor r13 was installed. Real
mid-page expansion, video reversal and page-switch responsiveness remain open acceptance items.

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
suspension, and a fourth native gesture UI scenario. All 64 tests passed in r6 run `35550153517`; real video playback and audio/video switching still need
physical verification. The fixture uses a generic colored view, not an actual decoder.

### r6 physical video diagnosis

r6 reached the physical iPhone and supplied the deeper read-only tree while video played on Home.
The classifier admitted video (`content-blockers=0`), but the adapter rejected its constraint profile
(`host=0`, `failed-placement=1`). The actual required aspect constraint belongs to the live surface,
not the enclosing video controller view. r7 replaces the inferred dimension fixture with that
captured ownership and preserves the surface's aspect constraint unchanged. Private run `35550785180` passed all 65 tests and built the IPA from `02ab166`. Physical
acceptance remains pending; the user reported no visible improvement with r6. The question of
whether audio expansion was separately retested after r6 is still unanswered.

### r7 physical rejection and r8 diagnostics

r7 was installed successfully over USB. Its first audio capture showed `host=1`, no blockers and
no placement failure. The user then reproduced video on Home: `host=0`, `failed-placement=1`,
content eligibility still zero. The profile now initializes, but placement returns the generic
`Spotify reclaimed source geometry during layout` message. Because restoration runs immediately,
the later tree contains natural sizes and cannot distinguish the failed condition.

r8 records the exact lease failure before restoration: surface hierarchy, aspect-constraint state,
measured source/card/media/video sizes, and changed placement/media constraints. It adds no relaxation
of the fitting rules and is diagnostic, not a claimed video fix. The regression asserts that a replaced
aspect constraint retains its specific failure reason after restoration. Physical animation status
is still unverified.

### r8 diagnosis and r9 candidate

The installed r8 captured `constraint lease: video aspect changed: active=0 constant=0.000 priority=1000` on the physical iPhone while video played on Home. The restored tree contained a new required 4:3 aspect constraint on the same live surface. Inspection of Spotify 9.1.78 also showed that `videoSurfaceDidChangeVideoRect:` rebuilds the aspect constraint even for an unchanged ratio.

The previous lease retained the old constraint object, so this normal replacement incorrectly revoked placement. r9 checks the current surface-owned constraint graph instead: exactly one compatible required aspect constraint, no new fixed dimensions, the same surface hierarchy, and the expected measured dimensions. It never writes or restores Spotify's aspect constraint. A different ratio, missing aspect, changed hierarchy or an extra dimension requirement still revokes the lease.

Regression coverage replaces equivalent constraints during `layoutIfNeeded` for landscape and portrait ratios, replaces them between placements while preserving original-button hit testing, and introduces an external dimension requirement. Physical r9 playback, scrolling, expansion and media switching remain unverified until installation and device testing.

Private run `35588127738` built r9 from `54a99bc438d1026424668462f903f1bb7344f879`. Attempt 1 passed 67/68 tests: all three new video regressions and the video UI scenario passed, but the constrained-audio expansion measurement failed. The retained trace shows a 440 ms gap between callbacks after only one aligned intermediate sample. An unchanged-code repeat (attempt 2) passed all 68 tests, with no skips. Both results are retained; this timing sensitivity and physical animation smoothness remain acceptance concerns, not a reason to weaken the assertion.

### r9 physical video result and r10 motion diagnostics

The user confirmed that r9 now collapses with video, but expansion still jumps. The live device snapshot showed an active host, no current placement failure, a 48-point live surface preserving its aspect, and a historical source-geometry rejection. That historical message alone cannot establish when the host was rebuilt.

r10 retains a bounded, diagnostic-only event history across host replacement. It records attachment/removal, media callbacks, placement environment and animation context, plus 0.8 seconds of presentation-layer samples after an expansion request. Sampling uses the display's default cadence without changing layout or playback. It runs only when FLEX is present. This distinguishes missing animation from host replacement on the physical iOS 27 device; r10 does not claim to fix expansion.

### Physical r10 expansion trace and r11 candidate

Independent iPhone Mirroring reproduction on iOS 27 confirms that upward scrolling changes the
accessory from inline to regular with `UIView.areAnimationsEnabled == NO` inside the `.never`
setter, despite the surrounding 0.36-second animation. The same host remains attached throughout;
the slot and live card jump from y=798 to y=735 between adjacent frames. This is not a host
replacement or a video-only defect. The user also reports that tapping a collapsed tab expands
smoothly and that ordinary page selection has become slow.

The r11 candidate removes policy writes during an active gesture and binds the real scroll view
only to the selected presentation proxy. UIKit retains ownership of both transition directions.
Ordinary tab actions retain the native host and live constraint lease instead of unconditionally
tearing them down; the existing transition, eligibility and geometry checks still release them.
Two coordinator regressions cover reselection and accepted navigation without host replacement.
Native reversal on the simulator and actual iPhone must pass before this candidate is accepted.

### r11 result and r12 expansion compatibility bridge

r11 passed all 66 unit tests but failed all four UI reversal checks on iOS 26.5. Physical testing
also distinguishes smooth automatic expansion at the beginning of a page from short upward
scrolls deep inside Library, where the native bar stays minimized. Therefore native automatic
behavior alone is insufficient for the requested interaction.

r12 isolates the private UIKit `_isMinimized` / `_setMinimized:` contract in `DynamicBarExpansion`.
The exact BOOL/void signatures were read from Apple's installed UIKit runtime and are checked on
the actual bar before every call. This revises the original public-API-only plan: the public
minimize-policy setter is unsuitable as an animated expansion command on the physical runtime.
Only our own native tab bar is affected; Spotify's views, controllers, gestures, video surface,
and navigation actions remain their original objects. No UIKit methods are hooked, no view
hierarchy or ivar is inspected, and no synthetic tap/scroll is sent. If the contract is missing
or changes, minimization is disabled. The scrolling policy remains `.onScrollDown` across the
explicit expansion. Actual swipe tests remain mandatory; metadata compatibility alone proves
neither animation nor future-OS support.

Both the diagnostic observer and harness frame sampler request the screen's available refresh
rate instead of leaving a default 60-Hz display link active during ProMotion transitions.

The user still reports slow/buggy page changes in r11. r12 additionally defers the original action
until UIKit's selection callback returns, and mirrors accepted controller identity immediately
instead of waiting for Spotify's label color and the 250 ms fallback repaint. Rejected actions do
not optimistically select a new page. Diagnostic counters measure refresh cost and time spent in
the original navigation action, so remaining stalls can be attributed on the phone. USB diagnostics
start after dylib loading finishes to avoid an initialization race with FLEX.

### r12 rejected before installation; r13 public-policy candidate

r12 built but failed validation: 67 tests passed and five failed. Direct `_setMinimized:` calls
raise Apple's "This can only be called by an approved app" exception. Signature matching was
insufficient. The candidate was **not installed**; the private calls and capability gate were
removed, and no attempt is made to bypass that restriction.

r13 returns to the public policy setter. A thread-local, main-thread-only compatibility scope
preserves the enclosing animation when UIKit calls `+[UIView performWithoutAnimation:]` during
that one write on our owned tab controller. Outside that scope the original implementation is
called, including on other threads. The scope ends in `@finally` before the explicit final layout.
This is a scoped method interception, not a private expansion API. Nonanimated and Reduce Motion
paths do not enter the scope. The diagnostic trace counts intercepted wrappers so the hypothesis
can be verified on the physical runtime; real gesture and isolation tests remain required.


Ordinary eligibility refreshes must not re-arm `.onScrollDown` during an upward gesture. r13
keeps the expansion policy until gesture end, or until a different scroll owner replaces the old
pan target. The regression test repeats eligibility and owner updates during an expansion request
and checks that only a real owner change re-arms minimization. Local Catalyst compilation with an
iOS 16.1 deployment floor also validates availability guards; this does not replace the iPhone build.


### Development checkpoint and stock-release restoration

At the user's request, development is paused after feature commit
`59f353a24f6908abedca7ca92422899489fdf6ec`. All source, regression tests and development
notes remain committed on `feat/dynamic-now-playing-tabbar`. The validation distinction above
remains: 72 tests passed for `0bc1dba`; the final eligibility-refresh regression has not run in CI.

The physical phone was returned to upstream **v0.21.0** using the maintainer's released tweak
binary, with experimental dynamic-bar code and FLEX absent. Its compiled support components use
unchanged upstream Live Activity/App Groups sources. Sideloadly reported **Done. 100%** for the
verified stock-release package. This installation is separate from the experimental branch and
does not constitute acceptance of the unfinished feature.
