#import "LuaRuntime.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

int luaopen_UIKitNative(lua_State *L);
int luaopen_Git(lua_State *L);

static UIWindow *gHostWindow;

UIWindow *LRTApplicationWindow(void) {
	return gHostWindow;
}

@implementation LRTApplicationController {
	UIWindow *_window;
	lua_State *_L;
	int _controllerRef;
	int _windowRef;
	LRTReloadConnection *_reloadConnection;
	BOOL _booted;
	BOOL _retrying;
	BOOL _waiting;
}

+ (instancetype)shared {
	static LRTApplicationController *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[self alloc] init]; });
	return shared;
}

- (instancetype)init {
	self = [super init];
	_controllerRef = LUA_NOREF;
	_windowRef = LUA_NOREF;
	return self;
}

- (NSString *)env:(NSString *)key fallback:(NSString *)fallback {
	const char *value = getenv(key.UTF8String);
	if (value && value[0]) return @(value);
	return fallback;
}

- (NSString *)packagerURL {
	return [self env:@"LUA_OBJC_PACKAGER" fallback:@"http://127.0.0.1:8081"];
}

- (void)startWithWindow:(UIWindow *)window {
	_window = window;
	gHostWindow = window;
	NSString *entry = [NSBundle.mainBundle objectForInfoDictionaryKey:@"LRTLocalEntry"];
	if (entry.length) {
		LRTResourceLoader.shared.localRoot = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Workspace"];
		LRTResourceLoader.shared.localEntry = entry;
	}
	LRTResourceLoader.shared.baseURL = [NSURL URLWithString:self.packagerURL];
	NSLog(@"[lua-objc] source=%@", LRTResourceLoader.shared.localRoot ?: self.packagerURL);
	[self tryBoot];
}

- (void)tryBoot {
	if (_booted) return;
	NSError *err = nil;
	if (![LRTResourceLoader.shared ping:&err]) {
		[self showWaiting];
		if (_retrying) return;
		_retrying = YES;
		__weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				if (!strongSelf) return;
				strongSelf->_retrying = NO;
				[strongSelf tryBoot];
			});
		return;
	}
	NSLog(@"[lua-objc] resources available");
	if (![self boot:&err]) {
		[self showError:err];
		return;
	}
	_booted = YES;
	_waiting = NO;
	NSLog(@"[lua-objc] boot ok");
	if (LRTResourceLoader.shared.localRoot) return;
	NSString *reloadURLString = [self.packagerURL stringByReplacingOccurrencesOfString:@"https://"
		withString:@"wss://"];
	reloadURLString = [reloadURLString stringByReplacingOccurrencesOfString:@"http://" withString:@"ws://"];
	if (![reloadURLString hasSuffix:@"/"]) reloadURLString = [reloadURLString stringByAppendingString:@"/"];
	NSURL *reloadURL = [NSURL URLWithString:[reloadURLString stringByAppendingString:@"hot"]];
	NSLog(@"[lua-objc] reload connection %@", reloadURL);
	_reloadConnection = [LRTReloadConnection new];
	__weak typeof(self) weakSelf = self;
	_reloadConnection.handler = ^(NSDictionary *event) {
		[weakSelf handleReloadEvent:event];
	};
	@try {
		[_reloadConnection connectToURL:reloadURL];
	} @catch (NSException *ex) {
		NSLog(@"[lua-objc] reload connection: %@", ex);
	}
}

- (void)showWaiting {
	if ([_window.rootViewController isKindOfClass:LRTErrorViewController.class]
		&& _waiting) return;
	_waiting = YES;
	_window.rootViewController = [[LRTErrorViewController alloc] initWaitingForPackager:self.packagerURL];
	[_window makeKeyAndVisible];
}

/* Plain-language status for a failed boot or reload. The raw message, such
 * as a Lua traceback, is kept for Copy Details. */
- (void)showError:(NSError *)error {
	NSString *details = error.localizedDescription ?: @"Unknown error";
	NSLog(@"[lua-objc] %@", details);
	NSString *title = @"Couldn’t Load App";
	NSString *message = [details componentsSeparatedByString:@"\n"].firstObject;
	if ([error.domain isEqualToString:@"LRTResourceLoader"] && error.code == 404) {
		title = @"File Not Found";
		message = [NSString stringWithFormat:
			@"The packager at %@ has no %@. It may be serving a project that was moved or deleted; restart it with make ios-run PROJECT=<app>.",
			self.packagerURL, error.userInfo[LRTResourceLoaderPathKey] ?: @"such file"];
	} else if ([error.domain isEqualToString:@"LRTApplicationController"]) {
		title = @"Lua Error";
	}
	_waiting = NO;
	__weak typeof(self) weakSelf = self;
	_window.rootViewController = [[LRTErrorViewController alloc] initWithTitle:title
		message:message details:details retry:^{ [weakSelf restart]; }];
	[_window makeKeyAndVisible];
}

// Try Again: rebuild the Lua state from the packager's current entry.
- (void)restart {
	[_reloadConnection disconnect];
	_reloadConnection = nil;
	_booted = NO;
	[self tryBoot];
}

static int searcher_packager(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "path");
	const char *searchPath = lua_tostring(L, -1);
	NSError *err = nil;
	NSString *src = [LRTResourceLoader.shared sourceForModule:@(name)
		searchPath:searchPath ? @(searchPath) : @"" error:&err];
	lua_pop(L, 2);
	if (!src) {
		lua_pushstring(L, err.localizedDescription.UTF8String ?: "not found");
		return 1;
	}
	NSData *bytes = [src dataUsingEncoding:NSUTF8StringEncoding];
	NSString *chunk = [NSString stringWithFormat:@"@%@", @(name)];
	if (luaL_loadbuffer(L, bytes.bytes, bytes.length, chunk.UTF8String) != LUA_OK) {
		return lua_error(L);
	}
	lua_pushstring(L, name);
	return 2;
}

static int bridge_read_file(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSError *err = nil;
	NSData *data = [LRTResourceLoader.shared dataForPath:@(path) error:&err];
	if (!data) {
		lua_pushnil(L);
		lua_pushstring(L, err.localizedDescription.UTF8String ?: "read failed");
		return 2;
	}
	lua_pushlstring(L, data.bytes, data.length);
	return 1;
}

- (BOOL)boot:(NSError **)error {
	if (_L) {
		lua_objc_prepare_close(_L);
		lua_close(_L);
		_L = NULL;
		_controllerRef = LUA_NOREF;
		_windowRef = LUA_NOREF;
	}
	_L = luaL_newstate();
	luaL_openlibs(_L);
	luaL_requiref(_L, "UIKitNative", luaopen_UIKitNative, 0);
	lua_pushcfunction(_L, bridge_read_file);
	lua_setfield(_L, -2, "_readFile");
	lua_pop(_L, 1);
	// iOS cannot load plugin dylibs from package.cpath, so the host links the
	// Git module (src/plugins/git) and offers it to require().
	luaL_getsubtable(_L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
	lua_pushcfunction(_L, luaopen_Git);
	lua_setfield(_L, -2, "Git");
	lua_pop(_L, 1);

	lua_getglobal(_L, "package");
	lua_getfield(_L, -1, "searchers");
	lua_Integer n = luaL_len(_L, -1);
	for (lua_Integer i = n + 1; i >= 2; i--) {
		lua_rawgeti(_L, -1, i - 1);
		lua_rawseti(_L, -2, i);
	}
	lua_pushcfunction(_L, searcher_packager);
	lua_rawseti(_L, -2, 1);
	lua_pop(_L, 2);

	if (luaL_dostring(_L, "local u = require('UIKit'); package.loaded.ns = u; package.loaded.AppKit = u; package.loaded.UIKit = u") != LUA_OK) {
		if (error) *error = [self luaError:@"UIKit"];
		return NO;
	}

	NSError *err = nil;
	NSString *entry = [LRTResourceLoader.shared entryPath:&err];
	if (!entry) {
		if (error) *error = err;
		return NO;
	}
	NSData *src = [LRTResourceLoader.shared dataForPath:entry error:&err];
	if (!src) {
		if (error) *error = err;
		return NO;
	}
	NSString *chunk = [NSString stringWithFormat:@"@%@", entry];
	if (luaL_loadbuffer(_L, src.bytes, src.length, chunk.UTF8String) != LUA_OK
		|| lua_pcall(_L, 0, 1, 0) != LUA_OK) {
		if (error) *error = [self luaError:@"entry"];
		return NO;
	}
	return [self instantiate:error];
}

- (BOOL)instantiate:(NSError **)error {
	while (lua_gettop(_L) > 0 && !lua_istable(_L, -1))
		lua_pop(_L, 1);
	if (!lua_istable(_L, -1)) {
		if (error) *error = [NSError errorWithDomain:@"LRTApplicationController" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"entry did not return a class"}];
		return NO;
	}
	lua_getfield(_L, -1, "new");
	if (!lua_isfunction(_L, -1)) {
		if (error) *error = [NSError errorWithDomain:@"LRTApplicationController" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"class has no new()"}];
		return NO;
	}
	/* class.new() takes no arguments; see src/main.m. */
	if (lua_pcall(_L, 0, 1, 0) != LUA_OK) {
		if (error) *error = [self luaError:@"new"];
		return NO;
	}
	lua_getfield(_L, -1, "createWindow");
	if (!lua_isfunction(_L, -1)) {
		if (error) *error = [NSError errorWithDomain:@"LRTApplicationController" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"no createWindow"}];
		return NO;
	}
	lua_pushvalue(_L, -2);
	if (lua_pcall(_L, 1, 1, 0) != LUA_OK) {
		if (error) *error = [self luaError:@"createWindow"];
		return NO;
	}
	if (_controllerRef != LUA_NOREF) luaL_unref(_L, LUA_REGISTRYINDEX, _controllerRef);
	if (_windowRef != LUA_NOREF) luaL_unref(_L, LUA_REGISTRYINDEX, _windowRef);
	lua_pushvalue(_L, -2);
	_controllerRef = luaL_ref(_L, LUA_REGISTRYINDEX);
	lua_pushvalue(_L, -1);
	_windowRef = luaL_ref(_L, LUA_REGISTRYINDEX);
	[_window makeKeyAndVisible];
	[self captureInternalScreenshotIfRequested];
	return YES;
}

- (void)captureInternalScreenshotIfRequested {
	NSString *requested = [self env:@"LUA_OBJC_INTERNAL_SCREENSHOT" fallback:@""];
	if (requested.length == 0) return;

	NSString *path = requested;
	if (![path hasPrefix:@"/"]) {
		path = [NSTemporaryDirectory() stringByAppendingPathComponent:path];
	}
	UIWindow *window = _window;
	dispatch_async(dispatch_get_main_queue(), ^{
		[window layoutIfNeeded];
		NSData *png = LRTCaptureViewPNG(window);
		NSError *error = nil;
		NSString *directory = [path stringByDeletingLastPathComponent];
		[[NSFileManager defaultManager] createDirectoryAtPath:directory
			withIntermediateDirectories:YES attributes:nil error:&error];
		BOOL ok = png && [png writeToFile:path options:NSDataWritingAtomic error:&error];
		if (ok) {
			NSLog(@"[lua-objc] internal screenshot written %@ (%lu bytes)",
				path, (unsigned long)png.length);
		} else {
			NSLog(@"[lua-objc] internal screenshot failed %@: %@",
				path, error.localizedDescription ?: @"empty view");
		}
	});
}

- (NSError *)luaError:(NSString *)context {
	NSString *msg = @"(no message)";
	if (_L && lua_gettop(_L) > 0 && lua_tostring(_L, -1)) {
		msg = @(lua_tostring(_L, -1));
	}
	return [NSError errorWithDomain:@"LRTApplicationController" code:1
		userInfo:@{NSLocalizedDescriptionKey:
			[NSString stringWithFormat:@"%@: %@", context, msg]}];
}

/* Every update recycles the lua_State. Re-running the entry inside the live
 * state cannot release the previous app: native views, targets and timers
 * hold registry references to Lua closures that capture the old controller,
 * a cycle across the two collectors that neither can break. Each in-place
 * reload therefore pinned a full view tree with its layer backing stores
 * (about 50 MB and 100 Mach ports on Adventure Arena). lua_close cancels
 * the state's timers and tasks and finalizes every userdata, so the whole
 * previous app goes at once. The resource cache keeps unchanged files, so
 * a reboot costs no more network than re-requiring modules did. */
- (void)handleReloadEvent:(NSDictionary *)event {
	if (![event[@"type"] isEqualToString:@"update"]) return;
	NSString *path = event[@"path"] ?: @"";
	NSLog(@"[lua-objc] update %@ %@", event[@"kind"] ?: @"", path);
	[LRTResourceLoader.shared dropCacheForPath:path];
	NSError *err = nil;
	if (![self boot:&err]) [self showError:err];
}

@end
