// Speech — on-device dictation for Lua apps without the software keyboard.
// SFSpeechRecognizer transcribes the microphone through AVAudioEngine; each
// change of state reaches Lua as onEvent(state, text, message) on the main
// thread: "starting", "listening", "partial" (text so far), "processing",
// "finished" (final text), "idle" or "error" (message). The module uses
// public Speech and AVFoundation APIs only. A Lua state never sees an event
// after it closes: closing runs each session's finalizer, which cancels it
// and forgets the state.

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Speech/Speech.h>
#import <lua.h>
#import <lauxlib.h>

static const char *SessionMetatable = "Speech.Recognizer";

@interface LuaSpeechSession : NSObject
@property(nonatomic) lua_State *L;           // the main thread; NULL once closed
@property(nonatomic) int callback;           // registry reference to onEvent
@property(nonatomic, copy) NSString *localeIdentifier;
@property(nonatomic, strong) SFSpeechRecognizer *recognizer;
@property(nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *request;
@property(nonatomic, strong) SFSpeechRecognitionTask *task;
@property(nonatomic, strong) AVAudioEngine *engine;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL starting;
@property(nonatomic) BOOL listening;
@property(nonatomic) BOOL finishing;
@property(nonatomic) BOOL tapInstalled;
- (void)cancelSilently;
@end

@implementation LuaSpeechSession

- (void)emitState:(NSString *)state text:(NSString *)text message:(NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		lua_State *L = self.L;
		if (!L) return;
		lua_rawgeti(L, LUA_REGISTRYINDEX, self.callback);
		lua_pushstring(L, state.UTF8String ?: "");
		lua_pushstring(L, text.UTF8String ?: "");
		lua_pushstring(L, message.UTF8String ?: "");
		if (lua_pcall(L, 3, 0, 0) != LUA_OK) {
			NSLog(@"Speech: %s", lua_tostring(L, -1));
			lua_pop(L, 1);
		}
	});
}

- (void)start {
	if (self.starting || self.listening || self.finishing) return;
	self.generation++;
	NSUInteger generation = self.generation;
	self.starting = YES;
	[self emitState:@"starting" text:@"" message:@""];

	__weak LuaSpeechSession *weakSelf = self;
	[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
		dispatch_async(dispatch_get_main_queue(), ^{
			LuaSpeechSession *session = weakSelf;
			if (!session || generation != session.generation) return;
			if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
				[session failWithMessage:@"Speech recognition access is denied."];
				return;
			}
			[AVAudioApplication requestRecordPermissionWithCompletionHandler:^(BOOL granted) {
				dispatch_async(dispatch_get_main_queue(), ^{
					LuaSpeechSession *current = weakSelf;
					if (!current || generation != current.generation) return;
					if (!granted) {
						[current failWithMessage:@"Microphone access is denied."];
						return;
					}
					[current beginListeningForGeneration:generation];
				});
			}];
		});
	}];
}

- (void)beginListeningForGeneration:(NSUInteger)generation {
	NSString *localeIdentifier = self.localeIdentifier.length
		? self.localeIdentifier : NSLocale.currentLocale.localeIdentifier;
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:localeIdentifier];
	SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
	if (!recognizer || !recognizer.isAvailable) {
		[self failWithMessage:@"Speech recognition is unavailable for the current language."];
		return;
	}

	NSError *audioError = nil;
	AVAudioSession *audioSession = AVAudioSession.sharedInstance;
	if (![audioSession setCategory:AVAudioSessionCategoryRecord
		mode:AVAudioSessionModeMeasurement options:0 error:&audioError]
		|| ![audioSession setActive:YES error:&audioError]) {
		[self failWithMessage:audioError.localizedDescription ?: @"The microphone could not be started."];
		return;
	}

	AVAudioEngine *engine = [[AVAudioEngine alloc] init];
	AVAudioInputNode *input = engine.inputNode;
	AVAudioFormat *format = [input outputFormatForBus:0];
	if (!format || format.sampleRate <= 0) {
		[self failWithMessage:@"The microphone has no available audio input."];
		return;
	}

	SFSpeechAudioBufferRecognitionRequest *request =
		[[SFSpeechAudioBufferRecognitionRequest alloc] init];
	request.shouldReportPartialResults = YES;
	request.taskHint = SFSpeechRecognitionTaskHintDictation;
	request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition;

	self.recognizer = recognizer;
	self.request = request;
	self.engine = engine;
	self.starting = NO;
	self.listening = YES;
	self.finishing = NO;

	__weak LuaSpeechSession *weakSelf = self;
	self.task = [recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
		if (!result && !error) return;
		NSString *transcript = result.bestTranscription.formattedString ?: @"";
		BOOL isFinal = result.isFinal;
		dispatch_async(dispatch_get_main_queue(), ^{
			LuaSpeechSession *session = weakSelf;
			if (!session || generation != session.generation) return;
			if (error) {
				[session failWithMessage:error.localizedDescription ?: @"Speech recognition failed."];
			} else if (isFinal) {
				[session completeWithText:transcript];
			} else {
				[session emitState:@"partial" text:transcript message:@""];
			}
		});
	}];

	AVAudioNodeTapBlock tapBlock = ^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
		[request appendAudioPCMBuffer:buffer];
	};
	BOOL tapInstalled = NO;
	if (@available(iOS 27.0, *)) {
		tapInstalled = [input installTapOnBus:0 bufferSize:1024 format:format
			error:&audioError block:tapBlock];
	} else {
		// The error-reporting overload requires iOS 27; keep the supported
		// iOS 26.5 deployment floor on the original install API.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[input installTapOnBus:0 bufferSize:1024 format:format block:tapBlock];
#pragma clang diagnostic pop
		tapInstalled = YES;
	}
	if (!tapInstalled) {
		[self failWithMessage:audioError.localizedDescription ?: @"The microphone tap could not be installed."];
		return;
	}
	self.tapInstalled = YES;
	[engine prepare];
	if (![engine startAndReturnError:&audioError]) {
		[self failWithMessage:audioError.localizedDescription ?: @"The microphone could not be started."];
		return;
	}
	[self emitState:@"listening" text:@"" message:@""];
}

- (void)stop {
	if (self.starting) {
		self.generation++;
		self.starting = NO;
		[self emitState:@"idle" text:@"" message:@""];
		return;
	}
	if (!self.listening) return;
	self.listening = NO;
	self.finishing = YES;
	[self stopAudioCapture];
	[self.request endAudio];
	[self emitState:@"processing" text:@"" message:@""];
}

- (void)cancel {
	[self cancelSilently];
	[self emitState:@"idle" text:@"" message:@""];
}

- (void)cancelSilently {
	self.generation++;
	self.starting = NO;
	self.listening = NO;
	self.finishing = NO;
	[self stopAudioCapture];
	[self.task cancel];
	self.task = nil;
	self.request = nil;
	self.recognizer = nil;
}

- (void)stopAudioCapture {
	if (self.tapInstalled) {
		[self.engine.inputNode removeTapOnBus:0];
		self.tapInstalled = NO;
	}
	if (self.engine.isRunning) [self.engine stop];
	self.engine = nil;
	[AVAudioSession.sharedInstance setActive:NO
		withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)completeWithText:(NSString *)text {
	[self stopAudioCapture];
	self.listening = NO;
	self.finishing = NO;
	self.task = nil;
	self.request = nil;
	self.recognizer = nil;
	[self emitState:@"finished" text:text message:@""];
}

- (void)failWithMessage:(NSString *)message {
	[self cancelSilently];
	[self emitState:@"error" text:@"" message:message];
}

@end

typedef struct {
	void *session; // CFBridgingRetain'd LuaSpeechSession
} SessionBox;

static LuaSpeechSession *check_session(lua_State *L) {
	SessionBox *box = luaL_checkudata(L, 1, SessionMetatable);
	if (!box->session) luaL_error(L, "speech recognizer is closed");
	return (__bridge LuaSpeechSession *)box->session;
}

// Speech.recognizer(onEvent [, locale]) -> recognizer; locale defaults to the
// user's.
static int recognizer(lua_State *L) {
	luaL_checktype(L, 1, LUA_TFUNCTION);
	const char *locale = luaL_optstring(L, 2, "");
	LuaSpeechSession *session = [[LuaSpeechSession alloc] init];
	lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
	session.L = lua_tothread(L, -1);
	lua_pop(L, 1);
	lua_pushvalue(L, 1);
	session.callback = luaL_ref(L, LUA_REGISTRYINDEX);
	session.localeIdentifier = @(locale);
	SessionBox *box = lua_newuserdatauv(L, sizeof(SessionBox), 0);
	box->session = (void *)CFBridgingRetain(session);
	luaL_setmetatable(L, SessionMetatable);
	return 1;
}

static int session_start(lua_State *L) { [check_session(L) start]; return 0; }
static int session_stop(lua_State *L) { [check_session(L) stop]; return 0; }
static int session_cancel(lua_State *L) { [check_session(L) cancel]; return 0; }

static int session_gc(lua_State *L) {
	SessionBox *box = luaL_checkudata(L, 1, SessionMetatable);
	if (!box->session) return 0;
	LuaSpeechSession *session = CFBridgingRelease(box->session);
	box->session = NULL;
	[session cancelSilently];
	luaL_unref(L, LUA_REGISTRYINDEX, session.callback);
	session.L = NULL;
	return 0;
}

int luaopen_Speech(lua_State *L) {
	if (luaL_newmetatable(L, SessionMetatable)) {
		const luaL_Reg methods[] = {{"start", session_start}, {"stop", session_stop}, {"cancel", session_cancel}, {NULL, NULL}};
		luaL_newlib(L, methods);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, session_gc);
		lua_setfield(L, -2, "__gc");
	}
	lua_pop(L, 1);
	const luaL_Reg functions[] = {{"recognizer", recognizer}, {NULL, NULL}};
	luaL_newlib(L, functions);
	return 1;
}
