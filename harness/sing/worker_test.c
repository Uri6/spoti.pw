// Real Core AI worker and production stream, driven at audio cadence with a local test fixture.
#include "Shared/Sing/SGSingStream.h"
#include "Shared/Sing/SGStemWorker.h"
#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static SGSingStream *stream;
static atomic_bool ready, finished, failed;
static float renderBuffer[882], *fixture;
static uint64_t pulled, audible;
static size_t fixtureFrames;
static bool injectStall;

static int32_t readInput(void *context, float *pcm, uint64_t *metadata) {
    assert(context == stream);
    int32_t state = SGSingStreamWorkerState(stream);
    if (state <= 0) return state;
    SGAudioStamp stamp;
    if (!SGSingStreamReadInput(stream, &stamp, pcm)) return 0;
    metadata[0] = stamp.generation; metadata[1] = stamp.track;
    metadata[2] = stamp.sourceFrame; metadata[3] = stamp.format;
    return stamp.frames;
}
static int32_t writeOutput(void *context, const float *pcm, uint32_t frames, uint64_t generation,
                            uint64_t track, uint64_t frame, uint32_t format) {
    assert(context == stream);
    if (SGSingStreamWorkerState(stream) < 0) return 0;
    // Delay one completed inference at the real worker boundary; the render cadence continues.
    if (injectStall && frame == 66150 * 4) usleep(2200000);
    return SGSingStreamWriteVocals(stream, (SGAudioStamp){generation,track,frame,format,frames}, pcm) ? 1 : -1;
}
static void report(void *context, int32_t status) {
    assert(context == stream);
    if (status == SGStemReady) atomic_store(&ready, true);
    if (status == SGStemFailed) {
        fprintf(stderr, "worker failed: timeline state %d, queued %llu\n", SGSingStreamState(stream),
                (unsigned long long)SGSingStreamQueued(stream));
        atomic_store(&failed, true);
    }
    if (status == SGStemFinished) atomic_store(&finished, true);
}
static int32_t source(void *context, uint32_t frames, float *pcm) {
    (void)context;
    for (unsigned n = 0; n < frames; n++) {
        size_t at = (pulled+n) % fixtureFrames;
        pcm[n*2] = fixture[at]; pcm[n*2+1] = fixture[fixtureFrames+at];
    }
    pulled += frames;
    return 0;
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec/1e9; }
int main(int argc, char **argv) {
    assert(argc >= 4 && argc <= 6); // model, hashes, golden input, optional cancel tick and stalled-output case
    unsigned cancelAt = argc >= 5 ? (unsigned)atoi(argv[4]) : 1200;
    injectStall = argc == 6;
    assert(cancelAt >= 200 && cancelAt <= 1200);
    FILE *file = fopen(argv[3], "rb"); assert(file);
    fseek(file, 0, SEEK_END); long bytes = ftell(file); rewind(file);
    assert(bytes > 0 && bytes % 8 == 0);
    fixture = malloc(bytes); assert(fixture && fread(fixture, 1, bytes, file) == (size_t)bytes); fclose(file);
    fixtureFrames = bytes / 8;
    stream = SGSingStreamCreate((SGAudioStamp){1,2,0,3,0}, 88200, 66150, 1); assert(stream);
    void *worker = SGStemWorkerStart(stream, argv[1], argv[2], 66150, readInput, writeOutput, report); assert(worker);
    double deadline = now()+60;
    while (!atomic_load(&ready) && !atomic_load(&finished) && now() < deadline) usleep(10000);
    assert(atomic_load(&ready) && !atomic_load(&failed));
    double start = now(), activation = 0;
    bool recovered = false, restored = false;
    for (unsigned tick = 0; tick < cancelAt + 450; tick++) {
        double wait = start + tick*.01 - now();
        if (wait > 0) usleep((unsigned)(wait*1e6));
        if (tick == cancelAt) SGSingStreamBypass(stream);
        assert(!SGSingStreamRender(stream, 441, renderBuffer, source, NULL));
        SGSingTimelineState state = SGSingStreamState(stream);
        if (state == SGSingTimelinePreparing) {
            for (unsigned n = 0; n < 882; n++) assert(renderBuffer[n] == 0);
        } else {
            if (!activation) activation = now()-start;
            for (unsigned n = 0; n < 441; n++) {
                size_t at = (audible+n) % fixtureFrames;
                assert(fabsf(renderBuffer[n*2] - fixture[at]) < 1e-6);
                assert(fabsf(renderBuffer[n*2+1] - fixture[fixtureFrames+at]) < 1e-6);
            }
            audible += 441;
            if (tick < cancelAt) {
                if (state == SGSingTimelineRecovering) { assert(injectStall); recovered = true; }
                else { assert(state == SGSingTimelineActive); if (recovered) restored = true; }
                assert(SGSingStreamStopReason(stream) == SGSingStopNone);
            }
        }
        assert(!atomic_load(&failed));
    }
    assert(activation > 2 && activation < 5);
    if (injectStall) assert(recovered && restored);
    assert(SGSingStreamState(stream) == SGSingTimelineIdle && pulled == audible);
    SGStemWorkerCancel(worker, 1);
    deadline = now()+5;
    while (!atomic_load(&finished) && now() < deadline) usleep(10000);
    assert(atomic_load(&finished));
    SGSingStreamDestroy(stream); free(fixture);
    printf("real worker: first audible %.3fs; %.2f seconds at cadence; exact original samples through active/cancellation and drain; recovery %s; finished safely\n",
           activation, (cancelAt + 450) / 100.0, injectStall ? "passed" : "not injected");
}
