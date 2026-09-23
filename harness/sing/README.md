# Sing feasibility and audio primitives

Sing is an opt-in implementation checkpoint. Model loading runs separately from playback, but
collecting the first aligned vocal reserve still produces a preparation gap, including after a
track change. Preparing while paused loads the model; it does not separate an entire paused song.
The selected vocal level survives track changes, but next-track pre-separation is not implemented.
Background continuation depends on a real GPU grant and was unavailable on the tested iPhone,
even with an authorized signing profile. A cool-device 90-second Spotify test passed; sustained
thermal, audible-continuity and lock-screen acceptance are still outstanding.

## Audio and model integration

`Shared/Audio/SGAudioPipeline.x` owns Spotify's mixer connection and RemoteIO observation once.
Sing operates on 44.1 kHz stereo source samples before time/pitch processing; output processing
runs speed/pitch, JamesDSP, then music haptics in a fixed order. The audio callback exchanges
generation/track/source-frame/format-stamped packets with an asynchronous Swift worker through
bounded single-producer/single-consumer queues. Model loading, hashing and inference never run
on that callback. The reconstructed mix is `original - (1 - level²) * vocals`, clamped to
[-1, 1], with a 30 ms level ramp and a 120 ms return to aligned original audio.

The separator is Mel-Band RoFormer with the pinned third-party checkpoint below. Apple's
[Core AI](https://developer.apple.com/documentation/coreai/aimodel) supplies the execution runtime;
the project does not include Apple's Music Sing model. The exporter re-exports the original
eight-second graph at a fixed two-second shape rather than truncating the original graph's input.
It uses the pinned Core AI PyTorch exporter, FP16 tensors, static shapes, and standard attention
operations instead of the training implementation's flash-attention path. Attention and rotary
position operations remain in the exported graph instead of being externalized by the exporter.

The host reflects the PCM boundaries into `[1, 2, 201, 2048]` frames, calls the graph's `main`
function through `AIModel`, `InferenceFunction` and `NDArray`, then overlap-adds `recon` with
window-weight normalization. STFT/iSTFT are part of the graph. A separate overlap-add combines
two-second model windows with a 1.5-second hop and a 0.5-second overlap, reducing inference count
by one third relative to the original one-second hop. The Swift actors serialize inference even
across retiring generations; cancelled/obsolete results cannot enter a new track's mix. A loaded
model is kept warm for 60 seconds, while memory/thermal failures purge it.

The packaged implementation uses the FP16 GPU-preferred graph, compiled ahead of time for the
device architecture. Payload hashes, architecture and tensor descriptors are validated before
use. The model is a separately supplied `Sing.bundle`; weights, compiled models and test audio
are not committed or downloaded during playback. Builds without Core AI support or the matching
bundle leave Sing unavailable.

Alternative backends were measured locally but are not selected by the packaged implementation:

| Experiment | Observation | Decision |
| --- | --- | --- |
| Weight-only INT8, FP16 GPU | Reduced model/memory size; slower in the measured Mac comparison | Not promoted based on size alone |
| FP16 CPU | Failed the golden-output parity check | Rejected |
| INT8 weights with FP32 CPU activations | Passed parity; missed 43 scheduling deadlines in a five-minute isolated iPhone run, even at a longer 1.625-second hop | Rejected for live integration |
| Neural Engine preferred, INT8 or six-bit palettized | AOT compilation succeeded; first iPhone inference aborted with an ANE/MPSGraph runtime error | Rejected; the exact runtime cause remains unknown |

A Neural Engine preference does not prove an exclusively Neural Engine graph; the experimental
artifacts contained both ANE and MPSGraph regions. No rejected backend, private queue probe or
experimental native-buffer patch is included in the production path.

## Checks

```sh
python3 harness/sing/test.py
TSAN=1 python3 harness/sing/test.py
python3 harness/sing/test_controller.py <booted-simulator-UDID>
python3 harness/sing/test_controller.py <booted-iOS-27-simulator-UDID> --background
python3 harness/sing/fetch_model.py --output /path/to/local/assets
xcrun swiftc -O -target arm64-apple-macos27.0 \
  tweak/Sources/Shared/Sing/SGStemSeparator.swift harness/sing/benchmark.swift -o /tmp/sing-benchmark
/tmp/sing-benchmark /path/to/local/assets /tmp/sing-benchmark.json
```

The C test runs the production packet queue and mixer with wraparound, queue pressure, 100,000
concurrent transfers, generation/track/format rejection, gain ramps, limiting and audible-clock
arithmetic. The timeline test checks exact source order through buffering, circular wraparound,
aligned bypass and draining, plus cancellation before preparation and a worker outage. The source
must stop pulling during a drain; only after the retained prefix is consumed may direct audio fill
the rest of a render buffer. The stream test exercises the actual source callback, worker packets,
pause, repeated level updates, cancellation and bounded queue pressure. It waits for a full window
of completed vocals before playing, so variations in inference duration don't consume the entire
bypass reserve. Production uses a two-second window with a 1.5-second hop and a half-second linear
overlap: one third fewer inferences than the original one-second hop. A two-minute regression
holds inference at 1.3 seconds, as observed on a warm phone, and checks every reduced sample
without entering recovery. The original 50% overlap and its 270/550/800 ms jitter test remain
covered. Startup still exceeds the original three-second target; model load and sustained thermal
performance require real-device measurement.
The controller test uses the real lifecycle and stream with deterministic player, worker and
AudioUnit boundaries: thermal gating/recovery, drain-before-retry, normal worker completion before
the polling timer, model retention and cancellation during loading. It also covers preparing a
model while paused before an audio graph exists, cancelling that prepared model without waiting
for Play, waiting for the graph to appear after Play (with a bounded timeout), keeping 70% vocals
through a loading/track transition, and preserving an explicit Off.
These tests do not constitute a live Spotify playback test.

Background ownership tests exercise entitlement and registration checks, asynchronous GPU grants,
actual processed-frame progress, cancellation, stale grants/expiration callbacks and submission
failures. The controller keeps the same worker when Spotify backgrounds with a grant; an expired
grant drains to the original audio. A temporary inactive state such as Control Center does not
cancel the worker. A device that reports no GPU support stops the worker in the background
without losing the selected level or repeatedly loading the model. Actual locked-screen/background
GPU execution still needs validation on a device that grants this resource.
Temporary audio interruptions pause the worker's input and retain the loaded model and grant;
completion of model loading during the interruption cannot attach audio until it ends. Spotify's
own play state determines whether audio resumes. These cases are covered by the controller test.

The vocal level is clamped to 20–100%, with the same endpoints in the mixer, controller and slider.
If vocal coverage drops below the bypass reserve, the timeline fades to the aligned original
while the worker continues. Results that are already audible are discarded; future results
restore the chosen mix once a half-window is available. A single 2.2-second inference stall is
tested at original and reduced volume, including a pause during recovery. Every source sample
is emitted once, without another buffering pause. A continuous eight seconds without recovery
still drains to direct audio. The controller tests recovery without reloading and cancellation
during recovery; thermal, memory and format failures retain their existing safeguards.

The serial window worker also has a Swift concurrency test, including reset during an inference:

```sh
xcrun swiftc -g -sanitize=thread -strict-concurrency=complete -warnings-as-errors \
  tweak/Sources/Shared/Sing/SGStemWindowProcessor.swift harness/sing/window_test.swift \
  -o /tmp/sing-window-test
/tmp/sing-window-test
```

The C bridge also runs the real model with the production hop at 44.1 kHz callback cadence, checking sample order through
activation and a drain back to direct audio, then disabling during an in-flight inference:

```sh
python3 harness/sing/test_worker.py /path/to/short.aimodel /path/to/hashes.json /path/to/golden_raw.f32
```

This uses ASan/UBSan for the C stream, or `--tsan` to instrument both the Swift worker and C transport.
It also delays one real inference result by 2.2 seconds and requires recovery at uninterrupted
render cadence, with exact original sample order through the temporary bypass and return.
The model store retains a warm model for 60 seconds, shares a pending load, and invalidates expired
loads when unloaded. Inference on a shared warm function is serialized across retiring generations.

The benchmark loads the real graph through the Swift Core AI adapter, compares four inferences
to the pinned golden vocals, and reports load/inference time and peak resident memory. The model
and golden files stay local. The downloader verifies pinned Git blob or LFS hashes, uses atomic
replacement, and fetches only model/test assets. It never sends audio anywhere.

`model.json` records the conversion, checkpoint, weights and Core AI bundle revisions. The
published graph is fixed at 352,800 stereo samples (eight seconds). Its worst measured warm inference time
plus eight seconds of input collection is the lower bound for causal live activation; faster-than-
real-time inference alone cannot establish the specification's three-second requirement.

For the short-window prototype, re-export the pinned conversion's `SepFull2` with `frames` shaped
`[1, 2, 201, 2048]` (two seconds) or `[1, 2, 401, 2048]` (four seconds). Do not truncate input to the
eight-second artifact and call it a short-window export. Compare against the same checkpoint at
the same shape, then evaluate the production overlap-add sequence against the eight-second reference and
a listening corpus. The Swift adapter derives its window size from the actual graph descriptor.
Changing shape requires a new artifact, hashes and golden outputs.

`export_model.py` exports either shape from pinned conversion and reference checkouts, the verified
checkpoint, and the original golden input. Its positional arguments name those four inputs and a
new output directory; `--seconds` is 2 or 4. Use the Core AI exporter revision in `model.json` and
its Python environment. Run `benchmark.swift` with the new directory, report path and `hashes.json`
as its third argument. The overlapped comparison uses the production window worker:

```sh
xcrun swiftc -O -target arm64-apple-macos27.0 \
  tweak/Sources/Shared/Sing/SGStemSeparator.swift \
  tweak/Sources/Shared/Sing/SGStemWindowProcessor.swift harness/sing/overlap.swift -o /tmp/sing-overlap
/tmp/sing-overlap /path/to/short-assets /path/to/reference-assets /tmp/sing-overlap.json
```

`overlap` accepts an optional final hop length in samples, defaulting to 66150 for the two-second
model. Use 44100 for comparison with the original overlap; both compare the same central region.
`corpus.swift` takes the model, hashes, corpus directory, output directory and an optional hop length.
Its comparisons exclude the first second and final two seconds at either hop, so a longer final
output packet cannot improve its score by including different source samples.
The golden comparison measures conversion parity and context changes on one fixture. It cannot
replace a varied listening corpus, supported-device measurements or a real playback endurance run.

For a supported iPhone, AOT-compile the short artifact with `xcrun coreai-build compile` for the
device's architecture, then build the isolated UIKit runner with Xcode's configured signing team:

```sh
python3 harness/sing/build_device.py --model /path/to/compiled.aimodelc \
  --goldens /path/to/short-assets --team YOUR_TEAM_ID
```

Install the resulting app using `xcrun devicectl device install app`. The bundle identifier is
`pw.spoti.harness.sing`. Launch it with `-duration 1800` for a 30-minute model load test, or without
arguments for eight inferences. Add `-waitForCool YES` to wait up to ten minutes for Nominal before
loading; with `devicectl process launch`, put `--` before these app arguments. The runner uses a dark
screen and schedules one inference every 1.5 seconds, matching the production hop. Pass
`-hopSeconds 1` to compare the old cadence. Reports include the requested hop and model source hash;
deadline misses include accumulated scheduling lateness. It records initial and final thermal state, cadence
misses, parity, peak RSS and the minimum remaining process memory allowance. It stops at Serious
or Critical heat and if it leaves the foreground. `Documents/progress.json` updates every ten
windows; `Documents/result.json` contains the completed result, retrievable with `devicectl device
copy from --domain-type appDataContainer`. The app contains only the supplied test goldens and
model; it does not capture audio or perform a Spotify playback test.

Before live integration, prove an aligned dry/processed bypass. Dropping a delayed queue when
disabling would jump forward; replaying already-audible source when enabling would jump backward.
The supplied specification explicitly excludes shipping that behavior. An eight-second diagnostic
result must not enable the production microphone control.

## Model provenance

The full-screen view, lyrics host, header, footer, controls and hosting controller names were
verified in the user-supplied Spotify **9.1.78** IPA. No Spotify binary or lyrics are committed.

Model provenance is pinned in [the manifest](model.json):

* [Conversion](https://github.com/john-rocky/coreai-model-zoo/tree/5029e6df8100650fe175d3e276fffb0177754ca1/conversion/melband_roformer).
* [Core AI artifact](https://huggingface.co/mlboydaisuke/MelBandRoformer-Vocal-CoreAI/tree/06f257a0d1d2ee4938595f872a23e9fc4c3fc97d), model card explicitly tagged MIT.
* [Checkpoint](https://huggingface.co/KimberleyJSN/melbandroformer/tree/ac9b0614ab3cd7f77219e18ba494dfd93956c348), weight repository explicitly tagged MIT.
* The host graph contract was checked against [KitSeparator](https://github.com/john-rocky/coreai-kit/blob/0a5933611ce91206d287b61ecdb94b5ec726b65e/Sources/CoreAIKit/Separation/KitSeparator.swift).

Attribution: Mel-Band RoFormer by Ju-Chiang Wang, Wei-Tsung Lu and Minz Won; the vocal checkpoint
by KimberleyJensen; lucidrains' BS-RoFormer implementation; ZFTurbo training code; the Core AI
conversion by john-rocky. Model weights, compiled artifacts and golden audio are not part of the
tweak package. A future package containing them must preserve the applicable MIT notices.


## Local Spotify build

`package_model.py MODEL.aimodelc out/Sing.bundle --architecture h18p` packages the
local two-second export, hashes every AOT payload, and includes the model's notices
and pinned provenance. Compile `export_model.py`'s output for the device with
`coreai-build` first. No model or test audio belongs in Git.

Pass `SING_MODEL_BUNDLE=/absolute/path/to/Sing.bundle` to the existing
`scripts/pipeline.sh` or `make release`. The normal build remains usable without
that optional resource. In the redesigned look, enable **Lyrics → Sing** and
restart Spotify. The microphone appears in the lyrics overlay opened by Now Playing's lyrics button;
its slider changes the running mixer without reloading the model. Unsupported
OS/hardware or a missing resource explains why Sing is unavailable.

Background processing also requires **Background GPU Access** on the app's signing target and a
provisioning profile that authorizes `com.apple.developer.background-tasks.continued-processing.gpu`.
The entitlement alone is insufficient: `BGTaskScheduler.supportedResources` must also contain
`.gpu` on the actual device. When it does not, the current GPU model cannot continue in the
background; adding or refreshing the signing profile does not remove that restriction.
`configure_background.py` adds the bundle-specific Sing task identifier and preserves Spotify's
existing background modes/identifiers. The pipeline and installer run it before signing; custom
signers that change the bundle ID must run it with `--bundle-id NEW_ID` before signing, too.
It does not grant an entitlement. iOS owns the task's progress/cancellation interface and can
expire its GPU grant; Sing then returns to the original audio. No inference runs on the audio thread.

The player integration now owns loading, 44.1 kHz stereo attachment, pause,
seek/track invalidation, thermal and memory fallback, and delayed-original drain.
Spotify's position getter, karaoke and the system now-playing elapsed time use
the same emitted-source clock while the adapter is attached. Device validation
of this integration, transitions between tracks and routes, and the 30-minute
thermal/continuity acceptance run are still required before release.
