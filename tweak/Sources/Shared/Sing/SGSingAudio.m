#include "SGSingAudio.h"
#include "Shared/Audio/SGAudioPipeline.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#include <math.h>

static _Atomic uint64_t epoch = 1, clockEpoch, clockTrack, clockBits;
static uint64_t bitsOf(double value) { uint64_t bits; memcpy(&bits, &value, sizeof bits); return bits; }
static double valueOf(uint64_t bits) { double value; memcpy(&value, &bits, sizeof value); return value; }
struct SGSingAudio {
    uint64_t epoch, track, origin;
    double position;
    _Atomic uint64_t latencyBits;
    SGSingStream *stream;
    const AudioTimeStamp *time; // borrowed only within the current render call
    float planar[2][SGSingStreamMaximumRenderFrames];
    float mixed[2 * SGSingStreamMaximumRenderFrames];
};
static int32_t pullOriginal(void *context, uint32_t frames, float *stereo) {
    SGSingAudio *a = context;
    struct { AudioBufferList list; AudioBuffer more; } data;
    data.list.mNumberBuffers = 2;
    for (unsigned c = 0; c < 2; c++) data.list.mBuffers[c] = (AudioBuffer){1, frames * sizeof(float), a->planar[c]};
    OSStatus error = SGAudioPipelinePullOriginal(frames, &data.list, a->time);
    if (!error) for (uint32_t n = 0; n < frames; n++)
        for (unsigned c = 0; c < 2; c++) stereo[n*2+c] = a->planar[c][n];
    return error;
}
static OSStatus process(void *context, UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time) {
    SGSingAudio *a = context;
    if (!data || data->mNumberBuffers != 2 || frames > UINT32_MAX / sizeof(float)) return kAudio_ParamError;
    for (unsigned c = 0; c < 2; c++)
        if (!data->mBuffers[c].mData || data->mBuffers[c].mNumberChannels != 1 || data->mBuffers[c].mDataByteSize < frames*sizeof(float))
            return kAudio_ParamError;
    if (a->epoch != atomic_load(&epoch)) {
        // A seek/skip has invalidated the old stems but main has not detached us yet. Follow
        // Spotify's current source during that interval, rather than muting its new audio.
        return SGAudioPipelinePullOriginal(frames, data, time);
    }
    a->time = time;
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(frames - done, SGSingStreamMaximumRenderFrames);
        OSStatus error = SGSingStreamRender(a->stream, count, a->mixed, pullOriginal, a);
        for (uint32_t n = 0; n < count; n++)
            for (unsigned c = 0; c < 2; c++) ((float *)data->mBuffers[c].mData)[done+n] = a->mixed[n*2+c];
        if (error) return error;
        done += count;
    }
    if (a->epoch != atomic_load(&epoch)) {
        for (unsigned c = 0; c < 2; c++) memset(data->mBuffers[c].mData, 0, frames * sizeof(float));
    } else if (a->track) {
        double position = a->position + (SGSingStreamPresented(a->stream) - a->origin) / 44100.0;
        position = fmax(a->position, position - valueOf(atomic_load(&a->latencyBits)));
        atomic_store(&clockBits, bitsOf(position));
        atomic_store(&clockTrack, a->track);
        atomic_store(&clockEpoch, a->epoch);
    }
    return noErr;
}
SGSingAudio *SGSingAudioCreate(SGAudioStamp origin, uint32_t window, uint32_t hop, float level) {
    SGSingAudio *a = calloc(1, sizeof *a);
    if (!a) return NULL;
    a->epoch = atomic_fetch_add(&epoch, 1) + 1; a->origin = origin.sourceFrame;
    a->stream = SGSingStreamCreate(origin, window, hop, level);
    if (!a->stream) { free(a); return NULL; }
    return a;
}
SGSingStream *SGSingAudioStream(SGSingAudio *a) { return a ? a->stream : NULL; }
bool SGSingAudioAttach(SGSingAudio *a) {
    AudioStreamBasicDescription format = {0};
    if (!a || a->epoch != atomic_load(&epoch) || !SGAudioPipelineSourceFormat(&format) || format.mSampleRate != 44100 || format.mChannelsPerFrame != 2 ||
        format.mFormatID != kAudioFormatLinearPCM || format.mBitsPerChannel != 32 || format.mBytesPerFrame != sizeof(float) ||
        !(format.mFormatFlags & kAudioFormatFlagIsFloat) || !(format.mFormatFlags & kAudioFormatFlagIsNonInterleaved)) return false;
    return SGAudioPipelineSetSourceProcessor(process, a);
}
void SGSingAudioDetach(SGSingAudio *a) {
    if (a && SGAudioPipelineClearSourceProcessor(a)) {
        uint64_t expected = a->epoch;
        atomic_compare_exchange_strong(&clockEpoch, &expected, 0);
    }
}
void SGSingAudioDestroy(SGSingAudio *a) {
    if (!a) return;
    SGSingStreamDestroy(a->stream); free(a);
}

void SGSingAudioInvalidate(void) { atomic_fetch_add(&epoch, 1); }
void SGSingAudioSetClock(SGSingAudio *a, double position, uint64_t track) {
    a->position = fmax(0, position); a->track = track;
}
void SGSingAudioSetLatency(SGSingAudio *a, double seconds) {
    atomic_store(&a->latencyBits, bitsOf(isfinite(seconds) ? fmax(0, seconds) : 0));
}
bool SGSingAudioClock(uint64_t track, double *position) {
    uint64_t ticket = atomic_load(&clockEpoch);
    if (!ticket || ticket != atomic_load(&epoch) || track != atomic_load(&clockTrack)) return false;
    double value = valueOf(atomic_load(&clockBits));
    if (ticket != atomic_load(&clockEpoch) || ticket != atomic_load(&epoch)) return false;
    *position = value;
    return true;
}
