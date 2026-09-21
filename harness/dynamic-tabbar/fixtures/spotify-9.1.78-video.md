# Video structure observed on device

Spotify 9.1.78, iOS 27.0, Home with a video actively playing, 2026-09-21. The user
confirmed this state and the USB capture contains the live surface below. This hand-reduced
record omits media text, account data, pointers and device identifiers. Raw trees remain private.

The source root, original parent, bar and card use the same 56-point structure as the
[audio capture](spotify-9.1.78-audio.md). Inside `now-playing-bar-content`:

```text
media wrapper 74.667 x 56
  media UIView 74.667 x 56
    BarVideoViewController.view 74.667 x 56
      SPTVideoSurfaceImpl 74.667 x 56
      hidden MaskView / cover-art fallback
track information and controls: 44 points high, centered at y=28
```

The content pins the media UIView top/bottom with zero padding and leading with zero inset.
Its width-equals-height constraint is priority 999; the live video occupies a measured 4:3 rectangle.
BarVideoViewController.view is pinned to that media UIView. Track information uses the same
`BarTrackInfoElementProps` identity as audio. No `ImageDataElementInput` is present.

The original diagnostic depth ended before the video view's own constraints. r6 extended the
capture and showed that **the controller view has no fixed dimension constraints**. Instead,
`SPTVideoSurfaceImpl` owns a required `width == height * 1.333333` constraint, with zero constant.
Four required zero edge pins attach the surface to the controller view. The hidden seek preview's
constraints follow that surface; they do not size the video independently.

The initial inferred fixed-dimension adapter in r6 rejected this graph before mutation, despite
its synthetic fixture passing. r7 replaces that inferred fixture with this captured graph: the
adapter changes only card height and root placement. Spotify's untouched surface aspect constraint
then computes the live width. A replaced/deactivated aspect constraint revokes ownership; restoring
the lease never reactivates Spotify's old aspect constraint. Tests reacquire after an aspect change
and verify that missing aspect constraints fail without changing the card.

Selectors `videoSurfaceDidAttachVideo:`, `videoSurfaceDidDetachVideo:` and
`videoSurfaceDidChangeVideoRect:` have `v24@0:8@16` encodings in 9.1.78 metadata. Hooks release
leased constraints before these callbacks and schedule re-evaluation after natural layout, keeping
the surface, its parent and CALayer unchanged. The UI fixture uses a colored UIView with the surface
identity, not a video decoder. Real playback continuity, scrubbing, fullscreen transitions and
repeated audio/video switches are still device acceptance checks.
