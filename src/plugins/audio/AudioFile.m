// AudioFile — reading, slicing and auditioning sound files for Lua apps.
// AVAudioFile decodes whatever Core Audio can open (WAV, AIFF, CAF, MP3,
// AAC, ALAC, FLAC); slices are written as uncompressed 24-bit WAV, which
// every sampler and DAW loads. Audition plays a span through one shared
// AVAudioEngine; nothing runs while it is silent.

#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <lua.h>
#import <lauxlib.h>

// Frames copied per read while exporting: 64k frames keep memory flat for
// slices of any length.
enum { kExportChunkFrames = 1 << 16, kExportBitDepth = 24 };

static AVAudioEngine *gEngine;
static AVAudioPlayerNode *gPlayer;
static AVAudioFile *gPlaying;

static AVAudioFile *openFile(lua_State *L, int index, NSError **error) {
	NSString *path = [NSString stringWithUTF8String:luaL_checkstring(L, index)];
	return [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:path] error:error];
}

static int pushError(lua_State *L, NSError *error, const char *fallback) {
	lua_pushnil(L);
	lua_pushstring(L, error.localizedDescription.UTF8String ?: fallback);
	return 2;
}

// Clamps a span in seconds to the file and returns it in frames.
static AVAudioFramePosition clampFrame(AVAudioFile *file, double seconds) {
	AVAudioFramePosition frame = (AVAudioFramePosition)llround(seconds * file.processingFormat.sampleRate);
	return MIN(MAX(frame, 0), file.length);
}

// info(path) -> {duration, frames, sampleRate, channels} or nil, message
static int info(lua_State *L) {
	NSError *error = nil;
	AVAudioFile *file = openFile(L, 1, &error);
	if (!file) return pushError(L, error, "The file is not a sound file.");
	double rate = file.processingFormat.sampleRate;
	lua_createtable(L, 0, 4);
	lua_pushnumber(L, rate > 0 ? (double)file.length / rate : 0); lua_setfield(L, -2, "duration");
	lua_pushinteger(L, file.length); lua_setfield(L, -2, "frames");
	lua_pushnumber(L, rate); lua_setfield(L, -2, "sampleRate");
	lua_pushinteger(L, file.processingFormat.channelCount); lua_setfield(L, -2, "channels");
	return 1;
}

// export(path, from, to, outPath) -> frames written, or nil, message.
// `from` and `to` are seconds; the slice keeps the source's rate and channels.
static int exportSlice(lua_State *L) {
	NSError *error = nil;
	AVAudioFile *source = openFile(L, 1, &error);
	if (!source) return pushError(L, error, "The file is not a sound file.");
	AVAudioFramePosition from = clampFrame(source, luaL_checknumber(L, 2));
	AVAudioFramePosition to = clampFrame(source, luaL_checknumber(L, 3));
	NSString *outPath = [NSString stringWithUTF8String:luaL_checkstring(L, 4)];
	if (to <= from) { lua_pushnil(L); lua_pushstring(L, "The slice is empty."); return 2; }

	AVAudioFormat *format = source.processingFormat;
	NSDictionary *settings = @{
		AVFormatIDKey: @(kAudioFormatLinearPCM),
		AVSampleRateKey: @(format.sampleRate),
		AVNumberOfChannelsKey: @(format.channelCount),
		AVLinearPCMBitDepthKey: @(kExportBitDepth),
		AVLinearPCMIsFloatKey: @NO,
		AVLinearPCMIsBigEndianKey: @NO,
		AVLinearPCMIsNonInterleaved: @NO};
	AVAudioFile *out = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:outPath] settings:settings
		commonFormat:format.commonFormat interleaved:format.isInterleaved error:&error];
	if (!out) return pushError(L, error, "The slice could not be written.");
	AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:kExportChunkFrames];
	source.framePosition = from;
	AVAudioFramePosition written = 0;
	while (from + written < to) {
		AVAudioFrameCount count = (AVAudioFrameCount)MIN((AVAudioFramePosition)kExportChunkFrames, to - from - written);
		if (![source readIntoBuffer:buffer frameCount:count error:&error] || buffer.frameLength == 0) break;
		if (![out writeFromBuffer:buffer error:&error]) return pushError(L, error, "The slice could not be written.");
		written += buffer.frameLength;
	}
	lua_pushinteger(L, written);
	return 1;
}

// The audition's end callback: a registry reference in the main Lua state.
// Each play bumps the generation, so a segment that was stopped or replaced
// never reports an end.
static lua_State *gMainState;
static int gOnEnd = LUA_NOREF;
static uint64_t gGeneration;

static void releaseOnEnd(void) {
	if (gMainState && gOnEnd != LUA_NOREF) luaL_unref(gMainState, LUA_REGISTRYINDEX, gOnEnd);
	gOnEnd = LUA_NOREF;
}

static void finished(uint64_t generation) {
	if (generation != gGeneration || gOnEnd == LUA_NOREF) return;
	int ref = gOnEnd;
	gOnEnd = LUA_NOREF;
	gPlaying = nil;
	lua_State *L = gMainState;
	lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
	luaL_unref(L, LUA_REGISTRYINDEX, ref);
	if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
		fprintf(stderr, "AudioFile onEnd: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
}

// stop(): silences the audition; its end callback does not run.
static int stop(lua_State *L) {
	(void)L;
	gGeneration++;
	releaseOnEnd();
	[gPlayer stop];
	[gEngine stop];
	gPlaying = nil;
	return 0;
}

// pause() keeps the position; resume() continues from it.
static int pausePlayback(lua_State *L) {
	(void)L;
	[gPlayer pause];
	return 0;
}

static int resume(lua_State *L) {
	(void)L;
	if (gPlaying) [gPlayer play];
	return 0;
}

// play(path, from, to, onEnd) -> true, or nil, message. Replaces what is
// playing; `onEnd()` runs on the main thread once the span has been heard.
static int play(lua_State *L) {
	NSError *error = nil;
	AVAudioFile *file = openFile(L, 1, &error);
	if (!file) return pushError(L, error, "The file is not a sound file.");
	AVAudioFramePosition from = clampFrame(file, luaL_checknumber(L, 2));
	AVAudioFramePosition to = clampFrame(file, luaL_optnumber(L, 3, (double)file.length / file.processingFormat.sampleRate));
	stop(L);
	if (to <= from) { lua_pushboolean(L, 1); return 1; }
	if (!gEngine) {
		gEngine = [AVAudioEngine new];
		gPlayer = [AVAudioPlayerNode new];
		[gEngine attachNode:gPlayer];
	}
	[gEngine disconnectNodeOutput:gPlayer];
	[gEngine connect:gPlayer to:gEngine.mainMixerNode format:file.processingFormat];
	if (![gEngine startAndReturnError:&error]) return pushError(L, error, "The audio device could not start.");
	gPlaying = file;
	if (lua_isfunction(L, 4)) {
		lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
		gMainState = lua_tothread(L, -1);
		lua_pop(L, 1);
		lua_pushvalue(L, 4);
		gOnEnd = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	uint64_t generation = gGeneration;
	[gPlayer scheduleSegment:file startingFrame:from frameCount:(AVAudioFrameCount)(to - from) atTime:nil
		completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
		completionHandler:^(AVAudioPlayerNodeCompletionCallbackType type) {
			(void)type;
			dispatch_async(dispatch_get_main_queue(), ^{ finished(generation); });
		}];
	[gPlayer play];
	lua_pushboolean(L, 1);
	return 1;
}

int luaopen_AudioFile(lua_State *L) {
	// Completion blocks are plugin code: keep the image mapped even if Lua
	// unloads the library while a segment is still playing.
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Dl_info image;
		if (dladdr((const void *)&luaopen_AudioFile, &image)) dlopen(image.dli_fname, RTLD_NOW | RTLD_NODELETE);
	});
	const luaL_Reg functions[] = {
		{"info", info}, {"export", exportSlice}, {"play", play}, {"pause", pausePlayback}, {"resume", resume},
		{"stop", stop}, {NULL, NULL}};
	luaL_newlib(L, functions);
	return 1;
}
