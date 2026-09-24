// Read-only look-ahead for the verified Spotify decoder. No private calls or PCM reads.
#pragma once
#import <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>

void SGAudioSourceQueueInitialize(void); // off-render, before registering source callbacks
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback);
// Sole source consumer only. Zero means no verified spare audio, including an event boundary.
// Inspect only the prefix needed for this pull; never walk the entire decoder queue needlessly.
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames);
