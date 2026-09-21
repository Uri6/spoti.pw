# Ordinary audio structure observed on device

Spotify 9.1.78, iOS 27.0, Redesigned look, 2026-09-20. This is a hand-reduced structural
record of a loaded, expanded audio bar. Media, account data, addresses and unrelated views
are omitted. The raw capture and screen recording are private. This is not evidence that
the dynamic presentation worked; the capture predates the user's failed scroll demonstration.

```text
NowPlayingBarContainerViewController
  NowPlayingBarViewController
    ContentViewControllerImplementation
      DurationViewController
```

All four controllers belong to `NowPlaying_BarImpl`. There is no `BarCoverArtViewController`
child. The displayed controller names are demangled; binary metadata uses mangled Swift names.
The content subtree includes:

```text
UIView 386x56 id=SPTNowPlayingBar
  UIView 386x56 id=now-playing-bar-content
    artwork wrapper 40x40 at (8,8)
      ElementView<ImageDataElementInput>
    information stack 330x40 at (48,8)
      InformationCollectionView > InformationCellV2
        ElementView<BarTrackInfoElementProps>
          promotional label > hidden stack
            JamListeningAlongLiveBadgeView [hidden]
```

The exact generic runtime names seen in the capture are:

- `_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI21ImageDataElementInputP_P__`
- `_TtGC13Element_UIKit11ElementViewV22NowPlaying_ElementsAPI24BarTrackInfoElementPropsP_P__`

`CapabilityTests` reproduces these positive identities and controller nesting, and checks that
hidden Jam scaffolding does not count as visible extra content. Adversarial cases remove/move
track information and add video or attachments; those are synthetic variations, not captured
video or Jam sessions. `CoordinatorTests` uses these audio identities for interruption tests.
These fixtures establish eligibility only; Spotify's own relayout and scrolling still require
device testing. In particular, a 56-point stock card may fail the native accessory's shorter slot.

## Constraint capture (2026-09-21, physical iPhone, r3)

Sanitized roles, no media text, pointer values or device identifiers:

- Source root: Auto Layout UIView, 402×56. Four required zero top/bottom/leading/trailing pins
  to its original 402×56 parent; a required self-height of 56.
- Bar controller view: four pins to source, with 8-point horizontal insets (386×56).
- `SPTNowPlayingBar`: leading/trailing/bottom pinned to bar view, required self-height 56.
- `now-playing-bar-content`: four zero pins to the card.
- Artwork: nested wrapper containing the known ImageData ElementView; top/bottom relative to
  content with 8-point padding. Width equals height at priority 999; measured 40×40.
- Text/control row: begins at artwork trailing, ends 8 points before content trailing, vertically
  contained in artwork bounds and centered. Controls measured 44 points wide, 40 high.

The reported card stayed 386×56 for a native 360×48 slot. `FixtureAudioPlayer` reproduces the
root/card/artwork constraints with generic UIKit views, labels and a real target-action button.
It is a structural regression fixture, not the Spotify binary or a validation of other variants.

### Enclosing layout discovered by r4

The root's parent is itself Auto Layout. Its height is implied by the source's four edge pins
and 56-point self-height, rather than by an independent parent height constraint. Its enclosing
passthrough view is bottom-anchored above the stock tabs and is 8 points taller than that parent.
After r4 released the source pins, the device reported the correctly resized 360×48 card at
`y=-332.5` in the native slot. The constraint lease now temporarily retains the original parent
height as well. The unit fixture asserts unambiguous layout, unchanged parent window position and
restoration; the constrained UI scenario uses a child-sized, bottom-anchored parent too.
