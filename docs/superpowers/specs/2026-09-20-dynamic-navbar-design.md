# Dynamic tab bar and Now Playing: implementation design for review

Date: 2026-09-20. Upstream: `skopevoj/spoti.pw`, commit `5b9579d2c4de9a2c84dc2417bfd24d662ee5c223`.
Working branch: `feat/dynamic-now-playing-tabbar`.
Status: design approved by the user on 2026-09-20; implementation and validation in progress.

## Outcome

In the Redesigned look on iOS 26+, scrolling down in a browsing page should move Now Playing into the bottom navigation row. Scrolling up should expand it again. Playback, navigation, video, Connect, Jam, accessibility, and opening/dismissing the full player must keep their existing behavior. The reference is the [video in issue #60](https://github.com/skopevoj/spoti.pw/issues/60).

“All cases covered” means that each case has an intentional, tested behavior. It does not mean forcing every Spotify presentation into a narrow row. If a presentation needs more room or cannot be identified safely, it remains expanded with all of its original controls.

## What the code establishes

- `Redesigned/Navbar/TabBar.x` renders a standalone `UITabBar` over Spotify's own tab bar. It forwards taps to the original items, mirrors selection, and adjusts safe-area space. It is not a `UITabBarController`.
- `Redesigned/NowPlayingBar/NowPlayingBar.x` restyles Spotify's actual mini-player. Spotify owns its labels, actions, gestures, and content updates. The current glass geometry and progress-line width assume an expanded card.
- `BarTransition.x` decorates Spotify's transition snapshots. `PlayerMorph.x` reads live card/artwork geometry and drives the full-player morph. Moving the mini-player independently would break these assumptions.
- `Shared/Player/PlayerState.x` publishes a useful but limited state subset. Its change key does not describe all video, Jam, route, ad, or auxiliary-banner states. It is not enough to recreate Spotify's mini-player faithfully.
- The 9.1.78 binary contains separate mini-player event sources for larger video, Jam listening-along, Connect, ads, accessibility text size, and additional “hat” content. These names establish that variants exist; they do not establish their runtime layout or usable selectors.
- Existing tab-bar and morph harnesses test selected geometry with mocked Spotify classes. They do not validate real video, Jam, all Spotify page insets, or every interactive transition.
- The maintainer specifically raised reimplementation and Jam complexity in [the discussion](https://github.com/skopevoj/spoti.pw/issues/60#issuecomment-5750203415).

## Options

| Approach | Benefit | Main risk | Decision |
| --- | --- | --- | --- |
| Preserve Spotify's mini-player behavior; add a presentation coordinator and a verified hosting/layout adapter | Retains existing actions and state handling; makes restoration and testing explicit | Hosting the live view safely still needs runtime proof | Recommended |
| Replace navigation containment with a real `UITabBarController`, using `UITabAccessory` | Native Apple minimization and inline layout | Can disrupt Spotify's controller ownership, navigation, insets, deep links, and snapshots | Test as a bounded feasibility experiment before choosing it |
| Rebuild the mini-player from shared playback state | Complete visual freedom | Missing state and actions for video, Jam, ads, Connect, and future variants | Reject as the starting point |

The first implementation milestone must resolve hosting feasibility. It must not turn an unproven controller transplant into a production dependency. If native containment cannot preserve the invariants below, retain Spotify's containment and implement only the presentation transition. Do not fabricate private selectors or manipulate UIKit's private tab-bar subviews to obtain minimization.

## Apple API and its limits here

Apple exposes minimization on `UITabBarController.tabBarMinimizeBehavior` with `UITabBarMinimizeBehaviorOnScrollDown`; accessory content belongs to `UITabAccessory`, assigned through `bottomAccessory`. The `tabAccessoryEnvironment` trait distinguishes regular and inline content layout. [Apple's UIKit demonstration](https://developer.apple.com/videos/play/wwdc2025/284/) shows this exact interaction.

These are controller APIs; they cannot simply be assigned to the current standalone `UITabBar`. `UIViewController.setContentScrollView(_:for:)` can designate the scroll view bars observe, but its documentation does not prove that an unrelated overlay controller can safely use Spotify's external page hierarchy. That must be tested. [Scroll-view API](https://developer.apple.com/documentation/uikit/uiviewcontroller/setcontentscrollview(_:for:)) · [Tab-bar controller](https://developer.apple.com/documentation/uikit/uitabbarcontroller)

## Ownership and component boundaries

1. **Spotify owns behavior.** Its playback model, decoder/video surface, gesture targets, navigation state, and controller lifecycle remain authoritative. Do not create a second player or infer playback actions from displayed labels.
2. **A coordinator owns presentation state.** One instance per relevant window/container, running on the main thread. It consumes scroll intent, visibility, geometry, accessibility, content capability, and transition events. It does not own media state.
3. **A mini-player adapter owns temporary layout changes.** It reports measured capabilities and acquires/relinquishes a presentation lease. Every changed property has an original value and a restoration path. Unknown structure fails to expanded before any mutation. View/controller ownership and touch delivery must be proved in the feasibility milestone.
4. **A navigation adapter preserves existing tab semantics.** Reordering, hidden/custom tabs, same-tab taps, external navigation, and Home long-press continue through the existing sources. The compact tab affordance must reveal navigation reliably; it must not strand hidden destinations.
5. **A geometry/transition bridge provides one coherent frame source.** Glass, artwork, progress, hit targets, safe areas, and full-player snapshots use the same presentation geometry. The coordinator must not animate geometry concurrently with Spotify's player transition.
6. **A pure policy layer is independently testable.** Given eligibility, scroll intent, and suspension reasons, it chooses expanded, compact, hidden, or suspended behavior. It does not reach into private Spotify classes.

Feature code stays in `Redesigned/`. Shared behavior changes, if needed for lifecycle events, must remain presentation-neutral. No imports from `Native/`; no persistent media metadata or recording of listening activity.

## Interaction policy

- Begin expanded. Collapse only after a deliberate downward movement in the active page's eligible vertical scroll view; expand on a deliberate upward movement or return to the top. Use a dead zone and direction-change hysteresis to avoid jitter.
- Ignore horizontal carousels, overscroll/bounce, programmatic jumps, refresh displacement, inactive pages, and the full player's dismissal scroll view. Do not replace Spotify's scroll delegate or disable its recognizers.
- Freeze presentation during full-player opening, interactive dismissal, cancelled gestures, navigation transitions, and layout ownership changes. Resume only after actual completion/cancellation and a fresh layout; a guessed timeout is insufficient.
- Treat keyboard presentation, rotation/size changes, foreground restoration, tab editing, controller replacement, and settings changes as reevaluation boundaries. Avoid stale async completions using a generation token.
- Reserve and release vertical space consistently with visual state, without moving the user's content position unexpectedly or covering the last row. Preserve existing Offline/Private Session banner insets.
- Compact controls keep meaningful touch targets, VoiceOver semantics, and a visible route back to expanded navigation. Titles truncate before controls shrink. Avoid gesture ambiguity between opening the player and play/pause.

## Behavior and validation matrix

| Situation | Required behavior | Evidence needed |
| --- | --- | --- |
| Ordinary audio, playing/paused/loading | Inline layout if measured controls fit; original controls and full-player opening work | Runtime tree, actions, compact/expanded screenshots |
| No current item, ended/stopped playback, launch/logout | No phantom mini-player; navigation remains usable | Lifecycle tests and device checks |
| Podcast/audiobook and changed transport controls | Preserve actual controls; compact only with an explicitly verified fitting layout | Variant trees and transport-action checks |
| Music video / video podcast / larger video bar | Preserve the actual video surface and playback state; expanded unless a video-specific inline layout is verified | Real video, tab switches, background/foreground, audio-only transitions |
| Canvas/animated artwork | Do not assume every animation is a video variant; preserve lifecycle and avoid duplicating rendering | Runtime structure and visual test |
| Jam host, guest, listening-along, live badges | Preserve entry points, status, role restrictions, joining/leaving updates; expand if extra content requires it | Real session tests; role/state transitions |
| Connect / AirPlay / remote-device playback | Keep device and route information, route controls, and remote actions accurate | Local-to-remote transitions and disconnected device |
| Ads / sponsored content / skip restrictions | Preserve required controls, badges, and restrictions; unknown presentations stay expanded | Eligible account/runtime evidence |
| Extra mini-player banner or tooltip | Keep it accessible and unclipped; expand before allocating its space | Actual extra-content layouts |
| Full-player open/close, cancelled interactive dismissal | Correct origin geometry; no ghost card, snapshot discontinuity, or hidden controls afterward | Both transition paths; rapid reversal; screenshots at intermediate progress |
| Tabs reordered/hidden/custom, one tab, Search hidden or selected | No invented navigation destinations; selection and return to expanded tabs remain correct | Existing editor combinations; deep link and repeated-tab tap |
| Narrow width, landscape, large text, RTL | Fit by measured geometry; otherwise expanded; no overlap or clipped touch targets | Width/text-size/RTL harness matrix and device spot checks |
| iPad / regular width | Preserve existing expanded behavior until a regular-width design is verified | Trait changes and iPad harness |
| VoiceOver / Reduce Motion / Reduce Transparency | Accessible controls and focus continuity; reduced animation and readable material | Accessibility-enabled checks |
| Offline/Private Session banner, keyboard, modal, tab-bar-hidden page | Honor Spotify's visibility and insets; no floating orphan player | Show/hide and interruption matrix |
| Memory pressure / view replacement / scene disconnect | Release observers and leases; no retained controllers or mutated orphan views | Repeated attach/detach tests |
| Future Spotify structure or unsupported API | Fail to the existing expanded presentation; diagnostic reason without personal content | Deliberately malformed/missing capability tests |

## Delivery sequence

1. **Feasibility evidence:** capture real hierarchies and ownership for baseline audio, video, and one expanded-extra-content variant; verify any new hook against the binary and runtime. Extend the harness to compare native accessory hosting against preserved containment. Record which option passes, with the remaining unknowns.
2. **Policy and restoration:** implement the state model and adapter lifecycle behind an explicit Redesigned setting, off by default during development. Test interruption, ineligibility, restoration, and stale completions independently.
3. **One complete audio path:** integrate navigation, active-page scroll ownership, live mini-player layout, dynamic progress geometry, accessibility, and full-player transitions. Make this genuinely interactive before broadening variants.
4. **Variant support:** add only evidence-backed compact layouts. Cover other variants with the documented expanded behavior and test transitions into/out of them while already compact.
5. **Validation:** layer checks; compile/package on a macOS runner with the iOS SDK; real UIKit harness across available runtimes and sizes; device matrix for Spotify-only behavior. A successful mock harness or compiler run is not evidence that video/Jam works on the phone.
6. **Reviewable contribution:** small commits, a focused architecture note, reproducible harness instructions, and a report distinguishing automated checks, device checks, and outstanding limitations. No upstream merge or release is part of this step.

## Release/rollback gates

The feature stays opt-in until the audio path and restoration contract pass on-device, and unverified variants demonstrably stay expanded. A single switch restores the existing presentation at next launch. No data migration or new backend is required. Build artifacts and the decrypted Spotify input stay out of the public source repository.

The local machine currently has Command Line Tools, without a full Xcode/iOS Simulator toolchain. Existing private macOS CI can compile the tweak; simulator and physical-device results must be reported separately. Runtime view captures may contain personal content and remain local, with only sanitized structural fixtures entering a contribution.

## Questions the feasibility milestone must answer

- Can the live mini-player be hosted at compact width without breaking controller containment, constraints, gesture coordinates, or video lifecycle?
- Can public UIKit minimization observe the actual active Spotify scroll view with correct navigation ownership, without private UIKit behavior?
- Where are the stable video/Jam/extra-content capability signals, and can they be detected before layout mutation?
- Which Spotify snapshot path is used for each presentation, and how is presentation geometry restored after cancellation?

If these cannot be demonstrated, the result is an evidence-backed feasibility report and a narrowed proposal, not a claim that the requested component is finished.
