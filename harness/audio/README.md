# Audio pipeline

```sh
python3 harness/audio/test.py
TSAN=1 python3 harness/audio/test.py
```

Runs the production pipeline against a deterministic Core Audio boundary on macOS, with
ASan/UBSan or ThreadSanitizer. Checks processor order, bounded source pulls, sample times,
silent buffers, failure after consuming input, connection/callback replacement, unsupported
formats, and disposal while rendering. The render thread must never wait for graph changes.

The real RemoteIO/effect tests remain in `harness/speed`, `harness/jamesdsp/sim`, and
`harness/haptics/sim`. These boundary tests do not establish device playback or Sing performance.
