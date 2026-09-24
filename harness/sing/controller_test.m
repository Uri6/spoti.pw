// Production controller with deterministic player/worker/AudioUnit boundaries. No model, Spotify
// binary or hardware thermal changes are needed. Stream buffering and retirement remain real.
#import "Shared/Sing/SGSingController.m"
#import <assert.h>

static SPTPlayerState *player;
static NSProcessInfoThermalState heat;
static unsigned starts, cancels, purges;
static BOOL paused, loading, outputAvailable = YES;
static NSString *trackURI = @"spotify:track:fixture";
static BOOL backgroundAllowed = YES;
static void (^backgroundChanged)(BOOL);
static void *attached;
static SGAudioSourceProcessor render;
static struct { void *context; SGStemStatus status; BOOL cancelled; } jobs[24];

@implementation SPTPlayerTrack
- (id)URI { return trackURI; }
@end
@implementation SPTPlayerState
- (SPTPlayerTrack *)track { static SPTPlayerTrack *track; if (!track) track = [SPTPlayerTrack new]; return track; }
- (BOOL)isPlaying { return !loading; }
- (BOOL)isPaused { return paused; }
- (BOOL)isLoading { return loading; }
- (double)duration { return 300; }
@end
void SGSingBackgroundStart(void (^changed)(BOOL)) { backgroundChanged = [changed copy]; }
void SGSingBackgroundEnd(void) { backgroundChanged = nil; }
BOOL SGSingBackgroundAllowed(void) { return backgroundAllowed; }
NSString *SGSingBackgroundExplanation(void) { return @"Background permission ended"; }
void SGSingBackgroundProgress(uint64_t generation, uint64_t completed, uint64_t total) {}
NSString *SGURIString(id uri) { return uri; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) { (void)observer; }
SPTPlayerState *SGPlayerState(void) { return player; }
double SGSingSourcePosition(SPTPlayerState *state) { return 10; }
double SGPlayerAudioLatency(void) { return 0; }
double SGPlayerSpeed(void) { return 1; }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
int32_t SGStemArchitectureMatches(const char *name) { return 1; }
void SGStemWorkerPurge(void) { purges++; }
void *SGStemWorkerStart(void *context, const char *path, const char *hashes, uint32_t hopFrames, SGStemRead read, SGStemWrite write, SGStemStatus status) {
    assert(starts < 24); unsigned n = starts++;
    jobs[n].context = context; jobs[n].status = status;
    return &jobs[n];
}
void SGStemWorkerCancel(void *handle, int32_t unload) {
    typeof(jobs[0]) *job = handle;
    assert(!job->cancelled); job->cancelled = YES; cancels++;
}
UInt32 SGAudioPipelineSourceAheadFrames(UInt32 maximumFrames) { return MIN(44100, maximumFrames); }
bool SGAudioPipelineSourceCanReadAhead(void) { return outputAvailable; }
bool SGAudioPipelineSourceProcessorAttached(void *context) { return context == attached; }
bool SGAudioPipelineSourceFormat(AudioStreamBasicDescription *format) {
    *format = (AudioStreamBasicDescription){44100, kAudioFormatLinearPCM,
        kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    return outputAvailable;
}
bool SGAudioPipelineSetSourceProcessor(SGAudioSourceProcessor callback, void *context) { attached = context; render = callback; return true; }
bool SGAudioPipelineClearSourceProcessor(void *context) { if (context != attached) return false; attached = NULL; return true; }
OSStatus SGAudioPipelinePullOriginal(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time) {
    for (unsigned c = 0; c < data->mNumberBuffers; c++)
        for (unsigned n = 0; n < frames; n++) ((float *)data->mBuffers[c].mData)[n] = .125f;
    return noErr;
}
static NSProcessInfoThermalState thermal(id self, SEL command) { return heat; }
static void flush(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
static void report(unsigned job, int status) { jobs[job].status(jobs[job].context, status); flush(); }
static int32_t source(void *context, uint32_t count, float *pcm) { memset(pcm, 0, count * 2 * sizeof(float)); return 0; }
int main(void) { @autoreleasepool {
    Class infoClass = object_getClass(NSProcessInfo.processInfo);
    Method getter = class_getInstanceMethod(infoClass, @selector(thermalState));
    class_replaceMethod(infoClass, @selector(thermalState), (IMP)thermal, method_getTypeEncoding(getter));
    player = [SPTPlayerState new];
    sg_configured = YES; sg_controller = [SGSingController new];
    sg_controller.state = SGSingIdle; sg_controller.active = YES;
    sg_controller.window = 88200; sg_controller.model = @"fixture"; sg_controller.hashes = @"fixture";
    assert(SGSingVocalLevel() == .2f && SGSingReducedLevel() == .2f);
    SGSingSetVocalLevel(-1); assert(SGSingVocalLevel() == .2f);
    SGSingSetVocalLevel(0); assert(SGSingVocalLevel() == .2f);

    heat = NSProcessInfoThermalStateSerious;
    assert(NSProcessInfo.processInfo.thermalState == heat);
    [sg_controller thermal:nil]; flush();
    assert(SGSingCurrentState() == SGSingIdle && starts == 0 && purges == 0);
    SGSingSetEnabled(YES);
    assert(SGSingCurrentState() == SGSingFailed && !SGSingCanRetry() && starts == 0);
    SGSingSetEnabled(YES);
    assert(starts == 0);
    assert(SGSingEnabled());
    SGSingSetEnabled(NO); // only an explicit Off clears the remembered choice
    heat = NSProcessInfoThermalStateFair;
    [sg_controller thermal:nil]; flush();
    assert(SGSingCurrentState() == SGSingIdle && starts == 0 && SGSingCanRetry());

    SGSingSetEnabled(YES); report(0, SGStemReady);
    assert(starts == 1 && sg_controller.session.attached);
    SGSingStream *s = stream(sg_controller.session);
    float pcm[882] = {0};
    // No inference result: fill the bounded input queue, then finish the worker BEFORE polling.
    for (unsigned n = 0; n < 1025 && SGSingStreamStopReason(s) == SGSingStopNone; n++)
        assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    assert(SGSingStreamStopReason(s) == SGSingStopCapacity);
    report(0, SGStemFinished);
    assert(SGSingCurrentState() == SGSingFailed && [SGSingExplanation() containsString:@"keep up"]);
    assert(purges == 0 && cancels == 1 && !SGSingCanRetry());
    SGSingSetEnabled(YES); assert(starts == 1);
    while (SGSingStreamState(s) != SGSingTimelineIdle) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile];
    assert(SGSingCanRetry() && !attached);

    SGSingSetEnabled(YES); report(1, SGStemReady);
    heat = NSProcessInfoThermalStateSerious;
    assert(NSProcessInfo.processInfo.thermalState == heat);
    [sg_controller thermal:nil]; flush();
    assert(SGSingCurrentState() == SGSingFailed && !SGSingCanRetry() && cancels == 2 && purges == 1);
    assert([SGSingExplanation() containsString:@"cool down"]);
    // A late finish must preserve the thermal explanation, not replace it with a model error.
    report(1, SGStemFinished);
    assert(SGSingCurrentState() == SGSingFailed && [SGSingExplanation() containsString:@"cool down"]);
    s = stream(sg_controller.session);
    assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile];
    assert(SGSingEnabled());
    SGSingSetEnabled(NO);
    heat = NSProcessInfoThermalStateFair; [sg_controller thermal:nil]; flush();
    assert(SGSingCurrentState() == SGSingIdle && starts == 2 && SGSingCanRetry());

    // Cancellation while loading retains its context until Finished and never overlaps workers.
    SGSingSetEnabled(YES); SGSingSetEnabled(NO); SGSingSetEnabled(YES);
    assert(starts == 3 && sg_controller.retired.count == 1 && SGSingCurrentState() == SGSingPreparing);
    report(2, SGStemFinished); assert(starts == 4 && sg_controller.retired.count == 0);
    SGSingSetEnabled(NO); report(3, SGStemFinished);
    assert(starts == cancels && !sg_controller.session && !sg_controller.retired.count);

    // Re-enable while attached audio drains. The UI acknowledges the new intent immediately,
    // but the next worker must wait for both the old audio and the old worker to finish.
    SGSingSetEnabled(YES); report(4, SGStemReady);
    s = stream(sg_controller.session);
    for (unsigned n = 0; n < 350; n++) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    float *vocals = calloc(132300, sizeof(float));
    SGAudioStamp stamp = {sg_controller.generation, SGSingTrackIdentifier(player.track.URI), 0, 1, 66150};
    for (unsigned n = 0; n < 4; n++, stamp.sourceFrame += 66150) assert(SGSingStreamWriteVocals(s, stamp, vocals));
    for (unsigned n = 0; n < 4; n++) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    free(vocals);
    [sg_controller reconcile]; assert(SGSingCurrentState() == SGSingActive);
    // App switching/locking retains the running worker and mix when the system grants GPU
    // background access. It must not drain, unload, or replace a playback generation.
    unsigned beforeBackground = cancels, beforePurges = purges;
    [sg_controller background:nil];
    assert(SGSingEnabled() && SGSingCurrentState() == SGSingActive && sg_controller.session.attached);
    assert(cancels == beforeBackground && purges == beforePurges && ![sg_controller restriction]);
    [sg_controller foreground:nil];
    assert(cancels == beforeBackground && SGSingCurrentState() == SGSingActive);
    SGSingSetEnabled(NO); assert(SGSingCurrentState() == SGSingDraining);
    SGSingSetEnabled(YES); assert(SGSingCurrentState() == SGSingPreparing && starts == 5);
    report(4, SGStemFinished);
    assert(starts == 5 && SGSingCurrentState() == SGSingPreparing);
    while (SGSingStreamState(s) != SGSingTimelineIdle) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile]; assert(starts == 6 && SGSingCurrentState() == SGSingPreparing);
    SGSingSetEnabled(NO); report(5, SGStemFinished);
    assert(starts == cancels && !attached && !sg_controller.session && !sg_controller.retired.count);

    // Arm while paused even when Spotify hasn't constructed a local audio graph yet.
    paused = YES; outputAvailable = NO;
    SGSingSetVocalLevel(.7f); SGSingSetEnabled(YES); report(6, SGStemReady);
    assert(SGSingEnabled() && SGSingCurrentState() == SGSingReady && !attached);
    assert(SGSingVocalLevel() == .7f && starts == 7);
    for (int n = 0; n < 10; n++) [sg_controller reconcile];
    assert(starts == 7 && SGSingCurrentState() == SGSingReady);
    // Spotify announces Play before constructing the local graph. Keep the prepared worker
    // across that interval instead of declaring the route unsupported on its first attempt.
    paused = NO; [sg_controller playerStateDidChange:player];
    assert(!attached && starts == 7 && cancels == 6 && SGSingCurrentState() == SGSingPreparing);
    for (int n = 0; n < 10; n++) [sg_controller reconcile];
    assert(starts == 7 && SGSingCurrentState() == SGSingPreparing);
    outputAvailable = YES; [sg_controller playerStateDidChange:player];
    assert(attached && starts == 7 && SGSingCurrentState() == SGSingPreparing);

    // Track transitions can report loading before a usable next state. Never lose 70% or
    // the user's enabled choice, and never run the old and new model workers together.
    loading = YES; trackURI = @"spotify:track:next";
    [sg_controller playerStateDidChange:player];
    assert(SGSingEnabled() && SGSingVocalLevel() == .7f && starts == 7 && !attached);
    report(6, SGStemFinished);
    assert(starts == 7 && SGSingCurrentState() == SGSingPreparing);
    loading = NO; [sg_controller playerStateDidChange:player]; report(7, SGStemReady);
    assert(starts == 8 && attached && SGSingEnabled() && SGSingVocalLevel() == .7f);
    // Commands invalidate stems before the main-thread handoff; current Spotify PCM must
    // remain audible during that gap instead of an extra silent render buffer.
    SGSingPlaybackWillChange();
    float left[32] = {0}, right[32] = {0};
    struct { AudioBufferList list; AudioBuffer more; } output;
    output.list.mNumberBuffers = 2;
    output.list.mBuffers[0] = (AudioBuffer){1, sizeof left, left};
    output.list.mBuffers[1] = (AudioBuffer){1, sizeof right, right};
    assert(!render(attached, 32, &output.list, NULL));
    for (int n = 0; n < 32; n++) assert(left[n] == .125f && right[n] == .125f);
    SGSingSetEnabled(NO); report(7, SGStemFinished);
    s = stream(sg_controller.session);
    assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100)); [sg_controller reconcile];
    trackURI = @"spotify:track:after-off"; [sg_controller playerStateDidChange:player];
    assert(!SGSingEnabled() && starts == 8 && SGSingVocalLevel() == .7f);
    paused = YES; SGSingSetEnabled(YES); report(8, SGStemReady);
    assert(attached && SGSingCurrentState() == SGSingReady);
    SGSingSetEnabled(NO); report(8, SGStemFinished);
    assert(!attached && !sg_controller.session && SGSingCurrentState() == SGSingIdle);
    // Thermal suspension retains intent without starting retry loops while the device is hot.
    SGSingSetEnabled(YES); report(9, SGStemReady);
    heat = NSProcessInfoThermalStateSerious; [sg_controller thermal:nil]; flush(); report(9, SGStemFinished);
    for (int n = 0; n < 10; n++) [sg_controller reconcile];
    assert(SGSingEnabled() && starts == 10 && !attached && !SGSingCanRetry());
    heat = NSProcessInfoThermalStateFair; [sg_controller thermal:nil]; flush(); report(10, SGStemReady);
    assert(SGSingEnabled() && SGSingCurrentState() == SGSingReady && SGSingVocalLevel() == .7f);
    SGSingSetEnabled(NO); report(10, SGStemFinished);
    assert(!attached && !sg_controller.session && starts == cancels);
    // A render-side delay is a recoverable state, not a model failure or a new user choice.
    paused = NO; SGSingSetVocalLevel(.7f); SGSingSetEnabled(YES); report(11, SGStemReady);
    s = stream(sg_controller.session);
    for (unsigned n = 0; n < 350; n++) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    vocals = calloc(132300, sizeof(float));
    stamp = (SGAudioStamp){sg_controller.generation, SGSingTrackIdentifier(player.track.URI), 0, 1, 66150};
    for (unsigned n = 0; n < 4; n++, stamp.sourceFrame += 66150) assert(SGSingStreamWriteVocals(s, stamp, vocals));
    for (unsigned n = 0; n < 4; n++) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile]; assert(SGSingCurrentState() == SGSingActive);
    while (SGSingStreamState(s) == SGSingTimelineActive) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile];
    assert(SGSingCurrentState() == SGSingRecovering && SGSingEnabled() && cancels == 11 && starts == 12);
    assert(SGSingStreamWriteVocals(s, stamp, vocals));
    assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile];
    // A single late hop is not enough to leave recovery. Wait for the full reserve
    // without spawning another worker or losing the user's selected vocal level.
    assert(SGSingCurrentState() == SGSingRecovering && SGSingVocalLevel() == .7f && starts == 12);
    stamp.sourceFrame += 66150;
    assert(SGSingStreamWriteVocals(s, stamp, vocals));
    assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile];
    assert(SGSingCurrentState() == SGSingActive && SGSingVocalLevel() == .7f && starts == 12);
    while (SGSingStreamState(s) == SGSingTimelineActive) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile]; assert(SGSingCurrentState() == SGSingRecovering);
    SGSingSetEnabled(NO); report(11, SGStemFinished);
    while (SGSingStreamState(s) != SGSingTimelineIdle) assert(!SGSingStreamRender(s, 441, pcm, source, NULL, 44100));
    [sg_controller reconcile]; free(vocals);
    assert(!SGSingEnabled() && !attached && starts == cancels);
    // An actually unavailable graph has a bounded wait and still offers an explanation.
    outputAvailable = NO; SGSingSetEnabled(YES); report(12, SGStemReady);
    assert(SGSingCurrentState() == SGSingPreparing && sg_controller.session.attachDeadline > CACurrentMediaTime());
    sg_controller.session.attachDeadline = CACurrentMediaTime() - 1;
    [sg_controller reconcile]; report(12, SGStemFinished);
    assert(SGSingCurrentState() == SGSingFailed && [SGSingExplanation() containsString:@"44.1"]);
    assert(!sg_controller.session && starts == cancels);
    SGSingSetEnabled(NO);
    // Expiration is different from a lifecycle event: preserve intent, stop the worker,
    // and don't retry a revoked grant in the background.
    outputAvailable = YES; paused = YES;
    SGSingSetEnabled(YES); report(13, SGStemReady);
    assert(SGSingCurrentState() == SGSingReady);
    beforeBackground = cancels;
    [sg_controller background:nil];
    assert(cancels == beforeBackground && SGSingCurrentState() == SGSingReady);
    backgroundAllowed = NO; assert(backgroundChanged); backgroundChanged(YES); report(13, SGStemFinished);
    assert(SGSingCurrentState() == SGSingFailed && SGSingEnabled() && !sg_controller.session);
    assert(cancels == beforeBackground + 1 && [SGSingExplanation() containsString:@"Background"]);
    for (int n = 0; n < 10; n++) [sg_controller reconcile];
    assert(starts == 14);
    SGSingSetEnabled(NO); backgroundAllowed = YES; [sg_controller foreground:nil];
    // Cancelling iOS's task UI must also stop work while Spotify is in the foreground.
    SGSingSetEnabled(YES); report(14, SGStemReady);
    assert(SGSingCurrentState() == SGSingReady && sg_controller.active);
    backgroundAllowed = NO; assert(backgroundChanged); backgroundChanged(YES); report(14, SGStemFinished);
    assert(SGSingCurrentState() == SGSingFailed && !sg_controller.session && starts == cancels);
    SGSingSetEnabled(NO);
    // A temporary audio interruption is not a cancellation, even if the model finishes loading
    // during it. Preserve the worker/grant and let Spotify's play state decide whether to resume.
    backgroundAllowed = YES; paused = NO;
    SGSingSetEnabled(YES);
    SGSingSession *interruptedSession = sg_controller.session;
    NSNotification *began = [NSNotification notificationWithName:AVAudioSessionInterruptionNotification object:nil
        userInfo:@{AVAudioSessionInterruptionTypeKey: @(AVAudioSessionInterruptionTypeBegan)}];
    NSNotification *ended = [NSNotification notificationWithName:AVAudioSessionInterruptionNotification object:nil
        userInfo:@{AVAudioSessionInterruptionTypeKey: @(AVAudioSessionInterruptionTypeEnded)}];
    [sg_controller interruption:began]; flush(); report(15, SGStemReady);
    assert(sg_controller.session == interruptedSession && interruptedSession.ready && !attached);
    assert(SGSingStreamWorkerState(stream(interruptedSession)) == 0 && starts == 16 && cancels == 15);
    [sg_controller background:nil]; assert(backgroundChanged);
    [sg_controller interruption:ended]; flush();
    assert(sg_controller.session == interruptedSession && attached && SGSingStreamWorkerState(stream(interruptedSession)) == 1);
    [sg_controller interruption:began]; flush();
    attached = NULL; [sg_controller reconcile];
    assert(sg_controller.session == interruptedSession && starts == 16 && cancels == 15);
    attached = interruptedSession.audio;
    [sg_controller interruption:ended]; flush();
    assert(sg_controller.session == interruptedSession && SGSingVocalLevel() == .7f);
    paused = YES; [sg_controller reconcile]; SGSingSetEnabled(NO); report(15, SGStemFinished);
    assert(!attached && !sg_controller.session && starts == cancels);
    // A valid signing entitlement does not guarantee device GPU support. If no grant was
    // available from the outset, backgrounding must stop work without losing the user's
    // level/intent or repeatedly loading a model which cannot run there.
    [sg_controller foreground:nil]; backgroundAllowed = NO;
    SGSingSetEnabled(YES); report(16, SGStemReady);
    assert(SGSingCurrentState() == SGSingReady && SGSingVocalLevel() == .7f);
    [sg_controller background:nil]; report(16, SGStemFinished);
    assert(!attached && !sg_controller.session && SGSingEnabled());
    assert(SGSingCurrentState() == SGSingFailed && [SGSingExplanation() containsString:@"Background"]);
    for (int n = 0; n < 10; n++) [sg_controller reconcile];
    assert(starts == 17 && starts == cancels);
    [sg_controller foreground:nil]; report(17, SGStemReady);
    assert(SGSingCurrentState() == SGSingReady && SGSingVocalLevel() == .7f);
    SGSingSetEnabled(NO); report(17, SGStemFinished);
    assert(!attached && !sg_controller.session && starts == cancels);
    // The CPU backend must not request a GPU task or stop when the app backgrounds without
    // GPU permission. Model loading, paused preparation and interruption retain their session.
    sg_controller.usesCoreML = YES;
    unsigned cpuPurges = purges;
    SGSingSetEnabled(YES);
    assert(!backgroundChanged && starts == 19);
    SGSingSession *cpuSession = sg_controller.session;
    [sg_controller background:nil]; report(18, SGStemReady);
    assert(sg_controller.session == cpuSession && SGSingCurrentState() == SGSingReady);
    assert(![sg_controller restriction] && purges == cpuPurges && !backgroundChanged);
    paused = NO; [sg_controller reconcile];
    assert(attached && SGSingStreamWorkerState(stream(cpuSession)) == 1);
    [sg_controller interruption:began]; flush();
    assert(sg_controller.session == cpuSession && SGSingStreamWorkerState(stream(cpuSession)) == 0);
    [sg_controller interruption:ended]; flush();
    assert(sg_controller.session == cpuSession && SGSingStreamWorkerState(stream(cpuSession)) == 1);
    [sg_controller foreground:nil];
    assert(!backgroundChanged && sg_controller.session == cpuSession && SGSingVocalLevel() == .7f);
    paused = YES; [sg_controller reconcile]; SGSingSetEnabled(NO); report(18, SGStemFinished);
    assert(!attached && !sg_controller.session && starts == cancels && purges == cpuPurges);
    puts("sing controller: thermal gating, retirement races, paused preparation, loading transitions, retained 70% and explicit Off passed");
} return 0; }
