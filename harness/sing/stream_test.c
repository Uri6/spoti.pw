#include "Shared/Sing/SGSingStream.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

enum { block = 441, window = 88200, hop = window / 2 };
static float output[4096 * 2], input[SGSingStreamPacketFrames * 2], vocals[window * 2];
static uint64_t pulled, audible, workerFrames, nextWindow;
static unsigned calls;
static bool fail;
static float signal(uint64_t frame) { return .3f * sinf((float)(frame % 44100) * .031f); }
static int32_t source(void *context, uint32_t count, float *pcm) {
    assert(context == &pulled); calls++;
    if (fail) return -42;
    for (unsigned n = 0; n < count; n++) { pcm[2*n] = signal(pulled+n); pcm[2*n+1] = -pcm[2*n]; }
    pulled += count;
    return 0;
}
static void worker(SGSingStream *s) {
    SGAudioStamp packet;
    while (SGSingStreamReadInput(s, &packet, input)) {
        assert(packet.sourceFrame == workerFrames);
        for (unsigned n = 0; n < packet.frames; n++) assert(input[n*2] == signal(workerFrames+n));
        workerFrames += packet.frames;
    }
    if (workerFrames >= nextWindow + window) {
        for (unsigned n = 0; n < hop; n++) {
            vocals[n*2] = .4f * signal(nextWindow+n); vocals[n*2+1] = -vocals[n*2];
        }
        assert(SGSingStreamWriteVocals(s, (SGAudioStamp){1, 2, nextWindow, 3, hop}, vocals));
        nextWindow += hop;
    }
}
static void render(SGSingStream *s, uint32_t count, bool silent, float gain) {
    assert(SGSingStreamRender(s, count, output, source, &pulled) == 0);
    for (unsigned n = 0; n < count; n++) {
        float expected = silent ? 0 : signal(audible+n) * gain;
        if (fabsf(output[n*2] - expected) >= 1e-5) {
            fprintf(stderr, "sample %llu: got %f expected %f, pulled %llu state %d\n",
                    (unsigned long long)(audible+n), output[n*2], expected,
                    (unsigned long long)pulled, SGSingStreamState(s));
            assert(false);
        }
        assert(fabsf(output[n*2] + output[n*2+1]) < 1e-6);
    }
    if (!silent) audible += count;
}
// Inference remains faster than the one-second hop but gets slower during playback, as it did
// inside Spotify. Ready-audio headroom must absorb that variation without stopping Sing.
static void inferenceJitter(void) {
    pulled = audible = workerFrames = nextWindow = 0;
    SGSingStream *s = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0}, window, hop, 1);
    unsigned due = 0, jobs = 0, activated = 0;
    for (unsigned tick = 0; tick < 1600; tick++) {
        SGAudioStamp packet;
        while (SGSingStreamReadInput(s, &packet, input)) workerFrames += packet.frames;
        if (!due && workerFrames >= nextWindow + window) due = tick + (jobs < 3 ? 27 : jobs % 2 ? 80 : 55);
        if (due && tick == due) {
            memset(vocals, 0, sizeof vocals);
            assert(SGSingStreamWriteVocals(s, (SGAudioStamp){1,2,nextWindow,3,hop}, vocals));
            nextWindow += hop; jobs++; due = 0;
        }
        assert(!SGSingStreamRender(s, block, output, source, &pulled));
        SGSingTimelineState state = SGSingStreamState(s);
        if (state == SGSingTimelinePreparing) {
            for (unsigned n = 0; n < block * 2; n++) assert(output[n] == 0);
        } else {
            assert(state == SGSingTimelineActive);
            if (!activated) activated = tick;
            for (unsigned n = 0; n < block; n++) assert(output[n*2] == signal(audible+n));
            audible += block;
        }
    }
    assert(activated > 300 && activated < 400 && jobs > 10);
    // If the worker actually stops, distinguish missing vocals from an inference exception.
    for (unsigned tick = 0; tick < 1200 && SGSingStreamStopReason(s) == SGSingStopNone; tick++)
        render(s, block, false, 1);
    assert(SGSingStreamStopReason(s) == SGSingStopLateVocals);
    SGSingStreamBypass(s);
    assert(SGSingStreamStopReason(s) == SGSingStopLateVocals); // retirement preserves the cause
    SGSingStreamDestroy(s);
}
// One late inference must not permanently disable an otherwise healthy worker. At unity
// gain every emitted sample must still match the original, including the recovery interval.
static void temporaryStall(float level) {
    pulled = audible = workerFrames = nextWindow = 0;
    SGSingStream *s = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0}, window, hop, level);
    unsigned due = 0, jobs = 0;
    bool activated = false;
    bool recovering = false, restored = false;
    float reducedGain = 1 - .4f * (1 - level * level);
    for (unsigned tick = 0; tick < 1800; tick++) {
        SGAudioStamp packet;
        while (SGSingStreamReadInput(s, &packet, input)) workerFrames += packet.frames;
        if (!due && workerFrames >= nextWindow + window) due = tick + (jobs == 5 ? 220 : 35);
        if (due && tick == due) {
            for (unsigned n = 0; n < hop; n++) {
                vocals[n*2] = .4f * signal(nextWindow+n); vocals[n*2+1] = -vocals[n*2];
            }
            assert(SGSingStreamWriteVocals(s, (SGAudioStamp){1,2,nextWindow,3,hop}, vocals));
            nextWindow += hop; jobs++; due = 0;
        }
        assert(!SGSingStreamRender(s, block, output, source, &pulled));
        if (SGSingStreamState(s) == SGSingTimelineRecovering && !recovering) {
            recovering = true;
            uint64_t capturedBefore = pulled, presentedBefore = SGSingStreamPresented(s);
            uint64_t queuedBefore = SGSingStreamQueued(s);
            float silent[block * 2];
            SGSingStreamPause(s, true);
            for (unsigned n = 0; n < 20; n++) {
                assert(!SGSingStreamRender(s, block, silent, source, &pulled));
                for (unsigned sample = 0; sample < block * 2; sample++) assert(silent[sample] == 0);
            }
            assert(capturedBefore == pulled && presentedBefore == SGSingStreamPresented(s) && queuedBefore == SGSingStreamQueued(s));
            SGSingStreamPause(s, false);
        }
        if (recovering && SGSingStreamState(s) == SGSingTimelineActive) restored = true;
        if (SGSingStreamState(s) != SGSingTimelinePreparing) {
            activated = true;
            for (unsigned n = 0; n < block; n++) {
                float original = signal(audible+n);
                if (level == 1) assert(output[n*2] == original);
                else {
                    if (fabsf(original) > 1e-6) {
                        float ratio = output[n*2] / original;
                        assert(ratio >= reducedGain - 1e-5 && ratio <= 1 + 1e-5);
                    }
                    if (tick > 1200) assert(fabsf(output[n*2] - original * reducedGain) < 1e-6);
                }
                assert(fabsf(output[n*2] + output[n*2+1]) < 1e-6);
            }
            audible += block;
        } else assert(!activated); // recovery must never rebuffer silence or reset its clock
        assert(SGSingStreamStopReason(s) == SGSingStopNone);
    }
    assert(activated && recovering && restored && jobs > 12 && SGSingStreamState(s) == SGSingTimelineActive);
    SGSingStreamDestroy(s);
}
// Reproduce the sustained 1.3-second inference time observed on a warm phone. A 1.5-second
// hop must stay reduced and aligned across ring wraps instead of repeatedly catching up.
static void sustainedInference(void) {
    const unsigned stride = window * 3 / 4;
    pulled = audible = workerFrames = nextWindow = 0;
    SGSingStream *s = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0}, window, stride, .7f);
    assert(s);
    unsigned due = 0, jobs = 0;
    for (unsigned tick = 0; tick < 12000; tick++) {
        SGAudioStamp packet;
        while (SGSingStreamReadInput(s, &packet, input)) workerFrames += packet.frames;
        if (!due && workerFrames >= nextWindow + window) due = tick + (jobs < 3 ? 35 : 130);
        if (due && tick == due) {
            for (unsigned n = 0; n < stride; n++) {
                vocals[n*2] = .4f * signal(nextWindow+n); vocals[n*2+1] = -vocals[n*2];
            }
            assert(SGSingStreamWriteVocals(s, (SGAudioStamp){1,2,nextWindow,3,stride}, vocals));
            nextWindow += stride; jobs++; due = 0;
        }
        assert(!SGSingStreamRender(s, block, output, source, &pulled));
        if (SGSingStreamState(s) == SGSingTimelinePreparing) {
            for (unsigned n = 0; n < block*2; n++) assert(output[n] == 0);
        } else {
            assert(SGSingStreamState(s) == SGSingTimelineActive);
            for (unsigned n = 0; n < block; n++) {
                assert(fabsf(output[n*2] - signal(audible+n) * .796f) < 1e-6);
                assert(fabsf(output[n*2] + output[n*2+1]) < 1e-6);
            }
            audible += block;
        }
        assert(SGSingStreamStopReason(s) == SGSingStopNone);
    }
    assert(jobs > 70);
    SGSingStreamDestroy(s);
}
int main(void) {
    sustainedInference();
    temporaryStall(1);
    temporaryStall(.7f);
    inferenceJitter();
    pulled = audible = workerFrames = nextWindow = 0;
    SGSingStream *s = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0}, window, hop, 0);
    assert(s);
    for (unsigned i = 0; i < 200; i++) { render(s, block, true, 0); worker(s); }
    assert(pulled == window && SGSingStreamQueued(s) == window);
    for (unsigned i = 0; i < 100; i++) { render(s, block, true, 0); worker(s); }
    for (unsigned i = 0; i < 900; i++) { render(s, block, false, .616f); worker(s); }
    uint64_t before = pulled, queued = SGSingStreamQueued(s);
    SGSingStreamPause(s, true);
    for (unsigned i = 0; i < 100; i++) render(s, block, true, 0);
    assert(pulled == before && SGSingStreamQueued(s) == queued);
    SGSingStreamPause(s, false);
    render(s, block, false, .616f); worker(s);
    SGSingStreamSetLevel(s, 1);
    // An unchanged control value must not restart the 30 ms gain ramp every callback.
    for (unsigned i = 0; i < 3; i++) {
        assert(!SGSingStreamRender(s, block, output, source, &pulled)); audible += block; worker(s);
    }
    render(s, block, false, 1); worker(s);
    before = pulled;
    SGSingStreamBypass(s);
    assert(SGSingStreamStopReason(s) == SGSingStopRequested);
    // Irregular render size exercises a buffer that contains both the final delayed prefix and
    // a fresh direct suffix. Every sample must remain in the original order, with no repeated pull.
    while (SGSingStreamState(s) != SGSingTimelineIdle) {
        render(s, 997, false, 1);
        if (SGSingStreamState(s) != SGSingTimelineIdle) assert(pulled == before);
    }
    assert(pulled == audible && !SGSingStreamQueued(s));
    render(s, 4096, false, 1);
    unsigned oldCalls = calls;
    fail = true;
    assert(SGSingStreamRender(s, 997, output, source, &pulled) == -42);
    assert(calls == oldCalls + 1);
    assert(!SGSingStreamWriteVocals(s, (SGAudioStamp){1,2,0,3,hop}, vocals));
    SGSingStreamDestroy(s);

    // A worker that never runs fills the bounded queue, then safely drains all retained input.
    fail = false; pulled = audible = 0;
    s = SGSingStreamCreate((SGAudioStamp){2,9,0,3,0}, window, hop, 0);
    for (unsigned i = 0; i < 1024; i++) render(s, 64, true, 0);
    render(s, 64, false, 1);
    assert(SGSingStreamState(s) == SGSingTimelineDraining);
    assert(SGSingStreamStopReason(s) == SGSingStopCapacity);
    while (SGSingStreamState(s) != SGSingTimelineIdle) render(s, 997, false, 1);
    assert(pulled == audible);
    SGSingStreamDestroy(s);
    fail = true;
    s = SGSingStreamCreate((SGAudioStamp){3,9,0,3,0}, window, hop, 0);
    assert(SGSingStreamRender(s, block, output, source, &pulled) == -42);
    assert(SGSingStreamStopReason(s) == SGSingStopSourceError && SGSingStreamSourceError(s) == -42);
    SGSingStreamDestroy(s);
    puts("sing stream: real source pulls, worker packets, pause, gain ramp, exact drain, errors and queue pressure passed");
}
