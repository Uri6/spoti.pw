# Immersive lyrics harness

The same inactivity policy, UIKit controller and karaoke renderer used by Now Playing. The compact
header remains visible while bottom controls fade and the existing lyrics viewport expands downward.
No Spotify binary or phone is needed. The player's own layout and hooks are covered
by `harness/player/` and by the actual Spotify device checks.

```sh
python3 harness/lyrics-immersive/test.py
THEOS=$HOME/theos DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 harness/lyrics-immersive/build.py
xcrun simctl install <iOS-26-simulator-UDID> harness/lyrics-immersive/build/LyricsImmersive.app
xcrun simctl launch --console-pty <UDID> pw.spoti.harness.immersive -test 1
python3 harness/lyrics-immersive/test_ui.py <UDID>
```

The portable test uses a fake monotonic clock and ASan/UBSan. The app checks real timers, opacity,
viewport expansion, preservation of lyric line views, menu holds and reopening. It aborts on a
failed assertion and prints `immersive ALL CHECKS PASSED` on success. `-song static` exercises
untimed text; `-song missing` exercises the no-lyrics state. The default uses the existing
anonymized multilingual `both.ttml` fixture, paused at 45 seconds.

The XCTest runner sends actual UIKit touches: reveal-only tap, repeat tap to seek, held touch,
menu presentation, scrolling, rotation and background/foreground. A test-only accessibility
probe reports observed state and seek count; it does not drive the production controller. The
generated Xcode project and screenshots stay in `build/ui`, with no signing-account information.

Manual checks: let chrome disappear, then tap a lyric once (reveal only) and again (seek); drag,
let momentum finish, and open/dismiss the translation menu. Check VoiceOver focus on controls,
Reduce Motion, rotation, background/foreground, and the same Now Playing lyrics overlay inside Spotify.
The harness does not prove Spotify's private hierarchy or device audio behavior.

If Documents is managed by iCloud, build a copied checkout in a local cache directory. Copy
fixture bytes without Finder metadata; codesign rejects resource forks on a built application.
