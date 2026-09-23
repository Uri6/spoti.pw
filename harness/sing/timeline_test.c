#include "Shared/Sing/SGSingTimeline.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

enum { block = 441, capacity = 44100 * 4 };
static float dry[block * 2], vocal[block * 2], output[block * 2];
static SGAudioStamp stamp(uint64_t at) { return (SGAudioStamp){7, 12, at, 1, block}; }
static float signal(uint64_t sample) { return .25f + .125f * sinf((float)(sample % 44100) * .013f); }
static void fill(uint64_t at) {
    for (unsigned i = 0; i < block; i++) {
        dry[i*2] = signal(at+i); dry[i*2+1] = -dry[i*2];
        vocal[i*2] = dry[i*2] * .4f; vocal[i*2+1] = -vocal[i*2];
    }
}
static void verify(uint64_t at, uint32_t count, float gain) {
    for (unsigned i = 0; i < count; i++) {
        assert(fabsf(output[i*2] - signal(at+i)*gain) < 1e-6);
        assert(fabsf(output[i*2] + output[i*2+1]) < 1e-6);
    }
}
int main(void) {
    assert(!SGSingTimelineCreate(0, 1));
    SGSingTimeline *t = SGSingTimelineCreate(capacity, block*2);
    assert(t);
    SGSingTimelineBegin(t, stamp(0), 0);
    uint64_t captured = 0, consumed = 0;
    // Two seconds of deliberate buffering; none of this PCM has been audible yet.
    for (unsigned i = 0; i < 200; i++) {
        fill(captured);
        assert(SGSingTimelineCapture(t, stamp(captured), dry));
        captured += block;
        assert(!SGSingTimelineRead(t, output, block));
        assert(SGSingTimelineConsumed(t) == 0);
    }
    for (uint64_t at = 0; at < captured; at += block) {
        fill(at); assert(SGSingTimelineVocals(t, stamp(at), vocal));
    }
    // Cross the circular buffer repeatedly while preserving exact source order.
    for (unsigned i = 0; i < 1000; i++) {
        fill(captured);
        assert(SGSingTimelineCapture(t, stamp(captured), dry));
        assert(SGSingTimelineVocals(t, stamp(captured), vocal));
        captured += block;
        assert(SGSingTimelineRead(t, output, block) == block);
        verify(consumed, block, .616f);
        consumed += block;
    }
    assert(SGSingTimelineGetState(t) == SGSingTimelineActive);
    SGSingTimelineBypass(t);
    assert(!SGSingTimelineWritable(t));
    assert(!SGSingTimelineCapture(t, stamp(captured), dry));
    assert(!SGSingTimelineVocals(t, stamp(captured), vocal));
    unsigned fadeBlocks = 0;
    while (SGSingTimelineQueued(t)) {
        uint32_t count = SGSingTimelineRead(t, output, block);
        assert(count == block);
        if (fadeBlocks++ >= 12) verify(consumed, count, 1);
        consumed += count;
    }
    assert(consumed == captured && SGSingTimelineGetState(t) == SGSingTimelineIdle);
    assert(SGSingTimelineConsumed(t) == captured);
    // No captured frame was skipped or replayed; the next direct pull begins at captured.
    SGSingTimelineBegin(t, (SGAudioStamp){8, 99, 1234, 2, block}, 0);
    assert(!SGSingTimelineVocals(t, stamp(0), vocal));
    assert(!SGSingTimelineCapture(t, stamp(1234), dry));
    assert(!SGSingTimelineCapture(t, (SGAudioStamp){8, 99, 1235, 2, block}, dry));
    assert(SGSingTimelineCapture(t, (SGAudioStamp){8, 99, 1234, 2, block}, dry));
    SGSingTimelineBypass(t); // cancelled before a model result: all buffered original still drains
    assert(SGSingTimelineRead(t, output, block) == block);
    for (unsigned i = 0; i < block*2; i++) assert(output[i] == dry[i]);
    assert(SGSingTimelineGetState(t) == SGSingTimelineIdle);
    // Permanent worker outage first keeps dry playback aligned, then expires its recovery budget
    // and releases the delay. The source keeps supplying audio until the terminal drain.
    SGSingTimelineBegin(t, stamp(0), 0);
    for (uint64_t at = 0; at < 44100; at += block) {
        fill(at); assert(SGSingTimelineCapture(t, stamp(at), dry));
        if (at < 8820) assert(SGSingTimelineVocals(t, stamp(at), vocal));
    }
    consumed = 0;
    captured = 44100;
    while (SGSingTimelineGetState(t) != SGSingTimelineIdle) {
        if (SGSingTimelineWritable(t)) {
            fill(captured); assert(SGSingTimelineCapture(t, stamp(captured), dry)); captured += block;
        }
        uint32_t count = SGSingTimelineRead(t, output, block);
        assert(count == block);
        if (consumed >= 8820 + 5292) verify(consumed, count, 1);
        for (unsigned i = 0; i < block*2; i++) assert(isfinite(output[i]) && fabsf(output[i]) <= 1);
        consumed += count;
    }
    assert(consumed == captured && consumed > SGSingRecoveryLimitFrames && SGSingTimelineGetState(t) == SGSingTimelineIdle);
    SGSingTimelineDestroy(t);
    puts("sing timeline: buffering, wraparound, exact source order, dry drain, stale results and worker outage passed");
}
