// AudioStream — a stereo PCM output queue for sample-generating Lua apps.
// Lua renders interleaved float frames on the main thread and writes them
// into a single-producer/single-consumer ring; an AVAudioSourceNode drains the
// ring on the realtime audio thread. The audio thread never touches Lua, so
// synthesis and composition stay in plain, headlessly testable Lua while the
// device clock stays glitch-free as long as Lua keeps the queue topped up.

#import <Accelerate/Accelerate.h>
#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <lua.h>
#import <lauxlib.h>
#import <stdatomic.h>

static const char *StreamMetatable = "AudioStream.Stream";

// Spectrum analysis window: 2048 frames is 46 ms at 44.1 kHz, short enough to
// follow a drum hit and long enough to separate sub bass partials.
enum { kAnalysisLog2 = 11, kAnalysisFrames = 1 << kAnalysisLog2 };
static const double kSpectrumFloorDb = -78, kSpectrumMinHz = 30, kSpectrumMaxHz = 16000;

// Frame counters only grow. The producer owns `written`, the consumer owns
// `played`; each reads the other's counter with acquire ordering so the
// samples between them are visible before the index that publishes them.
typedef struct {
	float *samples; // interleaved L/R, `capacity` frames
	uint64_t capacity;
	_Atomic uint64_t written;
	_Atomic uint64_t played;
	_Atomic uint64_t underruns;
	// Mono copy of the most recently played frames for visualisation. The
	// audio thread writes it; the main thread may read a frame mid-update,
	// which only affects one analysis and needs no lock.
	float history[kAnalysisFrames];
	uint32_t historyIndex;
} Ring;

@interface LuaAudioStream : NSObject
@property(nonatomic, strong) AVAudioEngine *engine;
@property(nonatomic, strong) AVAudioSourceNode *source;
@property(nonatomic) Ring *ring;
@property(nonatomic) double sampleRate;
@end

@implementation LuaAudioStream
- (void)dealloc {
	// Stopping the engine is synchronous: the render block cannot run after
	// it returns, so the ring can be freed safely.
	[_engine stop];
	if (_ring) {
		free(_ring->samples);
		free(_ring);
	}
}
@end

typedef struct {
	void *stream; // CFBridgingRetain'd LuaAudioStream
} StreamBox;

static LuaAudioStream *checkStream(lua_State *L, int index) {
	StreamBox *box = luaL_checkudata(L, index, StreamMetatable);
	if (!box->stream) luaL_error(L, "audio stream is closed");
	return (__bridge LuaAudioStream *)box->stream;
}

// open(sampleRate, capacityFrames) -> stream
static int streamOpen(lua_State *L) {
	double sampleRate = luaL_checknumber(L, 1);
	lua_Integer capacity = luaL_checkinteger(L, 2);
	luaL_argcheck(L, sampleRate >= 8000 && sampleRate <= 192000, 1, "sample rate out of range");
	luaL_argcheck(L, capacity > 0 && capacity <= (1 << 22), 2, "capacity out of range");

	Ring *ring = calloc(1, sizeof(Ring));
	ring->capacity = (uint64_t)capacity;
	ring->samples = calloc((size_t)capacity * 2, sizeof(float));

	AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];
	AVAudioSourceNode *source = [[AVAudioSourceNode alloc] initWithFormat:format
		renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *time, AVAudioFrameCount frames, AudioBufferList *output) {
			float *left = output->mBuffers[0].mData;
			float *right = output->mNumberBuffers > 1 ? output->mBuffers[1].mData : left;
			uint64_t played = atomic_load_explicit(&ring->played, memory_order_relaxed);
			uint64_t written = atomic_load_explicit(&ring->written, memory_order_acquire);
			uint64_t ready = written - played;
			uint64_t count = ready < frames ? ready : frames;
			for (uint64_t i = 0; i < count; i++) {
				const float *frame = ring->samples + ((played + i) % ring->capacity) * 2;
				left[i] = frame[0];
				right[i] = frame[1];
				ring->history[ring->historyIndex] = 0.5f * (frame[0] + frame[1]);
				ring->historyIndex = (ring->historyIndex + 1) & (kAnalysisFrames - 1);
			}
			for (uint64_t i = count; i < frames; i++) {
				left[i] = 0;
				right[i] = 0;
			}
			if (count < frames) atomic_fetch_add_explicit(&ring->underruns, 1, memory_order_relaxed);
			atomic_store_explicit(&ring->played, played + count, memory_order_release);
			return noErr;
		}];

	LuaAudioStream *stream = [LuaAudioStream new];
	stream.ring = ring;
	stream.sampleRate = sampleRate;
	stream.source = source;
	stream.engine = [AVAudioEngine new];
	[stream.engine attachNode:source];
	[stream.engine connect:source to:stream.engine.mainMixerNode format:format];

	StreamBox *box = lua_newuserdatauv(L, sizeof(StreamBox), 0);
	box->stream = (void *)CFBridgingRetain(stream);
	luaL_setmetatable(L, StreamMetatable);
	return 1;
}

// space(stream) -> frames that can be written without overwriting queued audio
static int streamSpace(lua_State *L) {
	Ring *ring = checkStream(L, 1).ring;
	uint64_t played = atomic_load_explicit(&ring->played, memory_order_acquire);
	uint64_t written = atomic_load_explicit(&ring->written, memory_order_relaxed);
	lua_pushinteger(L, (lua_Integer)(ring->capacity - (written - played)));
	return 1;
}

// write(stream, samples, frames) -> frames written. `samples` is a sequence of
// interleaved left/right numbers; values are clamped to [-1, 1].
static int streamWrite(lua_State *L) {
	Ring *ring = checkStream(L, 1).ring;
	luaL_checktype(L, 2, LUA_TTABLE);
	lua_Integer frames = luaL_checkinteger(L, 3);
	luaL_argcheck(L, frames >= 0, 3, "negative frame count");
	uint64_t played = atomic_load_explicit(&ring->played, memory_order_acquire);
	uint64_t written = atomic_load_explicit(&ring->written, memory_order_relaxed);
	uint64_t space = ring->capacity - (written - played);
	uint64_t count = (uint64_t)frames < space ? (uint64_t)frames : space;
	for (uint64_t i = 0; i < count; i++) {
		float *frame = ring->samples + ((written + i) % ring->capacity) * 2;
		for (int c = 0; c < 2; c++) {
			lua_rawgeti(L, 2, (lua_Integer)(i * 2 + c + 1));
			double value = lua_tonumber(L, -1);
			lua_pop(L, 1);
			frame[c] = (float)(value > 1 ? 1 : (value < -1 ? -1 : value));
		}
	}
	atomic_store_explicit(&ring->written, written + count, memory_order_release);
	lua_pushinteger(L, (lua_Integer)count);
	return 1;
}

// played(stream) -> total frames the device consumed, underrun count
static int streamPlayed(lua_State *L) {
	Ring *ring = checkStream(L, 1).ring;
	lua_pushinteger(L, (lua_Integer)atomic_load_explicit(&ring->played, memory_order_acquire));
	lua_pushinteger(L, (lua_Integer)atomic_load_explicit(&ring->underruns, memory_order_relaxed));
	return 2;
}

// Hann-windowed FFT of `mono` (kAnalysisFrames samples, oldest first) into
// `bands` log-spaced levels between 30 Hz and 16 kHz, each 0 (-78 dB) to 1
// (full scale). Pushes the band table and the RMS level.
static int pushSpectrum(lua_State *L, const float *mono, double sampleRate, int bands) {
	static FFTSetup setup;
	static float window[kAnalysisFrames];
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		setup = vDSP_create_fftsetup(kAnalysisLog2, kFFTRadix2);
		vDSP_hann_window(window, kAnalysisFrames, vDSP_HANN_NORM);
	});
	float windowed[kAnalysisFrames], real[kAnalysisFrames / 2], imag[kAnalysisFrames / 2];
	float power[kAnalysisFrames / 2];
	float rms = 0;
	vDSP_rmsqv(mono, 1, &rms, kAnalysisFrames);
	vDSP_vmul(mono, 1, window, 1, windowed, 1, kAnalysisFrames);
	DSPSplitComplex split = {real, imag};
	vDSP_ctoz((const DSPComplex *)windowed, 2, &split, 1, kAnalysisFrames / 2);
	vDSP_fft_zrip(setup, &split, 1, kAnalysisLog2, kFFTDirection_Forward);
	vDSP_zvmags(&split, 1, power, 1, kAnalysisFrames / 2);
	// zrip scales by 2 and the Hann window by 0.5; a full-scale sine peaks
	// at (N/2)^2 in power after both.
	double reference = (double)kAnalysisFrames * kAnalysisFrames / 4.0;
	double binHz = sampleRate / kAnalysisFrames;
	double ratio = log(kSpectrumMaxHz / kSpectrumMinHz);
	lua_createtable(L, bands, 0);
	for (int b = 0; b < bands; b++) {
		double lo = kSpectrumMinHz * exp(ratio * b / bands);
		double hi = kSpectrumMinHz * exp(ratio * (b + 1) / bands);
		int first = (int)floor(lo / binHz), last = (int)ceil(hi / binHz);
		if (first < 1) first = 1;
		if (last <= first) last = first + 1;
		if (last > kAnalysisFrames / 2) last = kAnalysisFrames / 2;
		double peak = 0;
		for (int k = first; k < last; k++) if (power[k] > peak) peak = power[k];
		double db = 10 * log10(peak / reference + 1e-12);
		double level = (db - kSpectrumFloorDb) / -kSpectrumFloorDb;
		lua_pushnumber(L, level < 0 ? 0 : (level > 1 ? 1 : level));
		lua_rawseti(L, -2, b + 1);
	}
	lua_pushnumber(L, rms);
	return 2;
}

static int checkBands(lua_State *L, int index) {
	lua_Integer bands = luaL_checkinteger(L, index);
	luaL_argcheck(L, bands > 0 && bands <= 256, index, "band count out of range");
	return (int)bands;
}

// spectrum(stream, bands) -> levels, rms of what the device just played
static int streamSpectrum(lua_State *L) {
	LuaAudioStream *stream = checkStream(L, 1);
	int bands = checkBands(L, 2);
	Ring *ring = stream.ring;
	float mono[kAnalysisFrames];
	uint32_t start = ring->historyIndex;
	for (int i = 0; i < kAnalysisFrames; i++) mono[i] = ring->history[(start + i) & (kAnalysisFrames - 1)];
	return pushSpectrum(L, mono, stream.sampleRate, bands);
}

// analyze(samples, sampleRate, bands) -> levels, rms. Analyses the last
// 2048 interleaved stereo frames of a Lua sequence (zero-padded if shorter);
// the same path `spectrum` uses, exposed so tests can feed known signals.
static int analyze(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	double sampleRate = luaL_checknumber(L, 2);
	int bands = checkBands(L, 3);
	lua_Integer frames = (lua_Integer)(lua_rawlen(L, 1) / 2);
	float mono[kAnalysisFrames] = {0};
	lua_Integer first = frames > kAnalysisFrames ? frames - kAnalysisFrames : 0;
	for (lua_Integer f = first; f < frames; f++) {
		lua_rawgeti(L, 1, f * 2 + 1);
		lua_rawgeti(L, 1, f * 2 + 2);
		mono[f - first] = (float)(0.5 * (lua_tonumber(L, -1) + lua_tonumber(L, -2)));
		lua_pop(L, 2);
	}
	return pushSpectrum(L, mono, sampleRate, bands);
}

static int streamStart(lua_State *L) {
	LuaAudioStream *stream = checkStream(L, 1);
	NSError *error = nil;
	if (![stream.engine startAndReturnError:&error]) {
		lua_pushnil(L);
		lua_pushstring(L, error.localizedDescription.UTF8String ?: "audio engine failed to start");
		return 2;
	}
	lua_pushboolean(L, 1);
	return 1;
}

// Pausing keeps queued frames, so resuming continues exactly where it stopped.
static int streamPause(lua_State *L) {
	[checkStream(L, 1).engine pause];
	return 0;
}

static int streamClose(lua_State *L) {
	StreamBox *box = luaL_checkudata(L, 1, StreamMetatable);
	if (box->stream) {
		CFBridgingRelease(box->stream);
		box->stream = NULL;
	}
	return 0;
}

int luaopen_AudioStream(lua_State *L) {
	// The render block is plugin code; keep the image mapped even if Lua
	// unloads the library before the engine has finished its last callback.
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Dl_info image;
		if (dladdr((const void *)&luaopen_AudioStream, &image)) dlopen(image.dli_fname, RTLD_NOW | RTLD_NODELETE);
	});
	luaL_newmetatable(L, StreamMetatable);
	lua_pushcfunction(L, streamClose); lua_setfield(L, -2, "__gc");
	lua_pop(L, 1);
	const luaL_Reg functions[] = {
		{"open", streamOpen}, {"space", streamSpace}, {"write", streamWrite},
		{"played", streamPlayed}, {"start", streamStart}, {"pause", streamPause},
		{"close", streamClose}, {"spectrum", streamSpectrum}, {"analyze", analyze}, {NULL, NULL}};
	luaL_newlib(L, functions);
	return 1;
}
