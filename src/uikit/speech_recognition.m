#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

@interface LuaSpeechRecognition : NSObject
@property(nonatomic, strong) LuaReg *callback;
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
- (instancetype)initWithCallback:(LuaReg *)callback localeIdentifier:(NSString *)localeIdentifier;
- (void)start;
- (void)stop;
- (void)cancel;
- (void)emitState:(NSString *)state text:(NSString *)text message:(NSString *)message;
- (void)beginListeningForGeneration:(NSUInteger)generation;
- (void)cancelSilently;
- (void)stopAudioCapture;
- (void)completeWithText:(NSString *)text;
- (void)failWithMessage:(NSString *)message;
@end

@implementation LuaSpeechRecognition

- (instancetype)initWithCallback:(LuaReg *)callback localeIdentifier:(NSString *)localeIdentifier {
	self = [super init];
	if (self) {
		_callback = callback;
		_localeIdentifier = [localeIdentifier copy];
	}
	return self;
}

- (void)emitState:(NSString *)state text:(NSString *)text message:(NSString *)message {
	LuaReg *callback = self.callback;
	if (!callback) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		lua_State *L = lua_reg_live_state(callback);
		if (!L || !lua_reg_push(callback)) {
			[self cancelSilently];
			return;
		}
		lua_pushstring(L, state.UTF8String ?: "");
		lua_pushstring(L, text.UTF8String ?: "");
		lua_pushstring(L, message.UTF8String ?: "");
		lua_objc_pcall(L, 3, 0, "speech recognition");
	});
}

- (void)start {
	if (self.starting || self.listening || self.finishing) return;
	self.generation++;
	NSUInteger generation = self.generation;
	self.starting = YES;
	[self emitState:@"starting" text:@"" message:@""];

	__weak LuaSpeechRecognition *weakSelf = self;
	[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
		dispatch_async(dispatch_get_main_queue(), ^{
			LuaSpeechRecognition *session = weakSelf;
			if (!session || generation != session.generation) return;
			if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
				[session failWithMessage:@"Speech recognition access is denied."];
				return;
			}
			[AVAudioApplication requestRecordPermissionWithCompletionHandler:^(BOOL granted) {
				dispatch_async(dispatch_get_main_queue(), ^{
					LuaSpeechRecognition *current = weakSelf;
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
	self.tapInstalled = YES;

	__weak LuaSpeechRecognition *weakSelf = self;
	self.task = [recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
		if (!result && !error) return;
		NSString *transcript = result.bestTranscription.formattedString ?: @"";
		BOOL isFinal = result.isFinal;
		dispatch_async(dispatch_get_main_queue(), ^{
			LuaSpeechRecognition *session = weakSelf;
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

	[input installTapOnBus:0 bufferSize:1024 format:format
		block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
			[request appendAudioPCMBuffer:buffer];
		}];
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

- (void)dealloc {
	[self cancelSilently];
	[_callback dispose];
}

@end

static int bridge_UIKitSpeechRecognition_create(lua_State *L) {
	luaL_checktype(L, 1, LUA_TFUNCTION);
	const char *locale = luaL_optstring(L, 2, "");
	LuaSpeechRecognition *session = [[LuaSpeechRecognition alloc]
		initWithCallback:lua_reg_create(L, 1, YES)
		localeIdentifier:[NSString stringWithUTF8String:locale]];
	push_objc(L, session, "nsobject");
	return 1;
}

static int bridge_UIKitSpeechRecognition_action(lua_State *L) {
	LuaSpeechRecognition *session = (LuaSpeechRecognition *)lua_objc_check_object(
		L, 1, [LuaSpeechRecognition class], "SpeechRecognizer");
	const char *action = luaL_checkstring(L, 2);
	if (strcmp(action, "start") == 0) [session start];
	else if (strcmp(action, "stop") == 0) [session stop];
	else if (strcmp(action, "cancel") == 0) [session cancel];
	else return luaL_error(L, "unknown speech-recognition action: %s", action);
	return 0;
}
