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
