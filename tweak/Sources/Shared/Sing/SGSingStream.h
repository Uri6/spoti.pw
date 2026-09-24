// One immutable playback generation. Create/retire off the audio thread, after its users stop.
// The render endpoint owns the timeline; the worker only exchanges stamped PCM packets.
#pragma once
#include "Shared/Sing/SGSingTimeline.h"

enum { SGSingStreamPacketFrames = 1024, SGSingStreamMaximumRenderFrames = 4096 };
typedef struct SGSingStream SGSingStream;
typedef enum {
    SGSingStopNone, SGSingStopRequested, SGSingStopLateVocals,
    SGSingStopCapacity, SGSingStopSourceError
} SGSingStopReason;
typedef int32_t (*SGSingSourceRead)(void *context, uint32_t frames, float *stereo);

SGSingStream *SGSingStreamCreate(SGAudioStamp origin, uint32_t windowFrames, uint32_t hopFrames, float level);
void SGSingStreamDestroy(SGSingStream *stream);
// Any thread; pause preserves this generation. Bypass is terminal and drains its original PCM.
void SGSingStreamPause(SGSingStream *stream, bool paused);
void SGSingStreamBypass(SGSingStream *stream);
void SGSingStreamSetLevel(SGSingStream *stream, float level);
SGSingTimelineState SGSingStreamState(const SGSingStream *stream);
uint64_t SGSingStreamPresented(const SGSingStream *stream);
uint64_t SGSingStreamQueued(const SGSingStream *stream);
uint64_t SGSingStreamReadyFrames(const SGSingStream *stream);
uint64_t SGSingStreamProcessed(const SGSingStream *stream);
SGSingStopReason SGSingStreamStopReason(const SGSingStream *stream);
int32_t SGSingStreamSourceError(const SGSingStream *stream);
int32_t SGSingStreamWorkerState(const SGSingStream *stream); // -1 stopped, 0 paused, 1 reading

// Render endpoint. Never pulls source while paused or draining. Preparation emits aligned original audio; only verified available frames permit extra pulls.
int32_t SGSingStreamRender(SGSingStream *stream, uint32_t frames, float *stereo,
                          SGSingSourceRead source, void *context, uint32_t available);
// Worker endpoint. Input holds 1024 stereo frames; output holds one completed hop.
bool SGSingStreamReadInput(SGSingStream *stream, SGAudioStamp *stamp, float *stereo);
bool SGSingStreamWriteVocals(SGSingStream *stream, SGAudioStamp stamp, const float *stereo);
