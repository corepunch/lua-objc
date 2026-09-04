#import "LuaHost.h"
#import "LuaSourceLoader.h"
#import "LuaHotClient.h"
#import "LuaErrorOverlay.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

int luaopen_UIKitNative(lua_State *L);

static UIWindow *gHostWindow;

UIWindow *lua_objc_host_window(void) {
	return gHostWindow;
}

@implementation LuaHost {
	UIWindow *_window;
	lua_State *_L;
	int _controllerRef;
	int _windowRef;
	LuaHotClient *_hot;
	NSMutableDictionary<NSString *, NSString *> *_modulePaths;
	id _preservedModel;
}

+ (instancetype)shared {
	static LuaHost *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [[self alloc] init]; });
	return shared;
}

- (instancetype)init {
	self = [super init];
	_controllerRef = LUA_NOREF;
	_windowRef = LUA_NOREF;
	_modulePaths = [NSMutableDictionary dictionary];
	return self;
}

- (NSString *)env:(NSString *)key fallback:(NSString *)fallback {
	const char *value = getenv(key.UTF8String);
	if (value && value[0]) return @(value);
	return fallback;
}

- (void)startWithWindow:(UIWindow *)window {
	_window = window;
	gHostWindow = window;
	NSString *packager = [self env:@"LUA_OBJC_PACKAGER"
		fallback:@"http://127.0.0.1:8081"];
	NSLog(@"[lua-objc] packager=%@", packager);
	LuaSourceLoader.shared.baseURL = [NSURL URLWithString:packager];
	NSError *err = nil;
	if (![LuaSourceLoader.shared ping:&err]) {
		[self showError:[NSString stringWithFormat:
			@"Packager not running.\nmake ios-run ARGS=…\n\n%@",
			err.localizedDescription]];
		return;
	}
	NSLog(@"[lua-objc] packager reachable");
	if (![self boot:&err]) {
		[self showError:err.localizedDescription ?: @"boot failed"];
		return;
	}
	NSLog(@"[lua-objc] boot ok");
	NSString *hot = [packager stringByReplacingOccurrencesOfString:@"https://"
		withString:@"wss://"];
	hot = [hot stringByReplacingOccurrencesOfString:@"http://" withString:@"ws://"];
	if (![hot hasSuffix:@"/"]) hot = [hot stringByAppendingString:@"/"];
	NSURL *hotURL = [NSURL URLWithString:[hot stringByAppendingString:@"hot"]];
	NSLog(@"[lua-objc] hot %@", hotURL);
	_hot = [LuaHotClient new];
	__weak typeof(self) weakSelf = self;
	_hot.handler = ^(NSDictionary *event) {
		[weakSelf handleHot:event];
	};
	@try {
		[_hot connectToURL:hotURL];
	} @catch (NSException *ex) {
		NSLog(@"[lua-objc] hot client: %@", ex);
	}
}

- (void)showError:(NSString *)message {
	NSLog(@"[lua-objc] %@", message);
	_window.rootViewController =
		[[LuaErrorOverlay alloc] initWithMessage:message];
	[_window makeKeyAndVisible];
}

static int searcher_packager(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	NSError *err = nil;
	NSString *src = [LuaSourceLoader.shared sourceForModule:@(name) error:&err];
	if (!src) {
		lua_pushstring(L, err.localizedDescription.UTF8String ?: "not found");
		return 1;
	}
	NSData *bytes = [src dataUsingEncoding:NSUTF8StringEncoding];
	if (luaL_loadbuffer(L, bytes.bytes, bytes.length, name) != LUA_OK) {
		return lua_error(L);
	}
	lua_pushstring(L, name);
	LuaHost *host = LuaHost.shared;
	[host recordModule:@(name)];
	return 2;
}

- (void)recordModule:(NSString *)name {
	_modulePaths[name] = name;
}

static int bridge_read_file(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSError *err = nil;
	NSData *data = [LuaSourceLoader.shared dataForPath:@(path) error:&err];
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
		lua_close(_L);
		_L = NULL;
	}
	_L = luaL_newstate();
	luaL_openlibs(_L);
	luaL_requiref(_L, "UIKitNative", luaopen_UIKitNative, 0);
	lua_pushcfunction(_L, bridge_read_file);
	lua_setfield(_L, -2, "_readFile");
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
	NSString *entry = [LuaSourceLoader.shared entryPath:&err];
	if (!entry) {
		if (error) *error = err;
		return NO;
	}
	NSData *src = [LuaSourceLoader.shared dataForPath:entry error:&err];
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
		if (error) *error = [NSError errorWithDomain:@"LuaHost" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"entry did not return a class"}];
		return NO;
	}
	lua_getfield(_L, -1, "new");
	if (!lua_isfunction(_L, -1)) {
		if (error) *error = [NSError errorWithDomain:@"LuaHost" code:1
			userInfo:@{NSLocalizedDescriptionKey: @"class has no new()"}];
		return NO;
	}
	lua_pushvalue(_L, -2);
	if (lua_pcall(_L, 1, 1, 0) != LUA_OK) {
		if (error) *error = [self luaError:@"new"];
		return NO;
	}
	if (_preservedModel && lua_istable(_L, -1)) {
		/* restore later via Lua table assignment if present */
	}
	lua_getfield(_L, -1, "createWindow");
	if (!lua_isfunction(_L, -1)) {
		if (error) *error = [NSError errorWithDomain:@"LuaHost" code:1
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
	return YES;
}

- (NSError *)luaError:(NSString *)context {
	NSString *msg = @"(no message)";
	if (_L && lua_gettop(_L) > 0 && lua_tostring(_L, -1)) {
		msg = @(lua_tostring(_L, -1));
	}
	return [NSError errorWithDomain:@"LuaHost" code:1
		userInfo:@{NSLocalizedDescriptionKey:
			[NSString stringWithFormat:@"%@: %@", context, msg]}];
}

- (void)unrequireExceptModel {
	lua_getglobal(_L, "package");
	lua_getfield(_L, -1, "loaded");
	lua_pushnil(_L);
	NSMutableArray *keys = [NSMutableArray array];
	while (lua_next(_L, -2)) {
		if (lua_isstring(_L, -2)) {
			NSString *name = @(lua_tostring(_L, -2));
			BOOL keep = [name isEqualToString:@"UIKitNative"]
				|| [name isEqualToString:@"package"]
				|| [name hasSuffix:@".Model"]
				|| [name isEqualToString:@"Model"];
			if (!keep) [keys addObject:name];
		}
		lua_pop(_L, 1);
	}
	for (NSString *name in keys) {
		lua_pushnil(_L);
		lua_setfield(_L, -2, name.UTF8String);
	}
	lua_pop(_L, 2);
}

- (void)handleHot:(NSDictionary *)event {
	NSString *type = event[@"type"];
	if ([type isEqualToString:@"hello"]) return;
	if (![type isEqualToString:@"update"]) return;
	NSString *kind = event[@"kind"] ?: @"";
	NSString *path = event[@"path"] ?: @"";
	NSLog(@"[lua-objc] update %@ %@", kind, path);
	if ([kind isEqualToString:@"asset"]) {
		[LuaSourceLoader.shared dropCacheForPath:path];
	}
	NSError *err = nil;
	if ([kind isEqualToString:@"model"] || [kind isEqualToString:@"init"]) {
		if (![self boot:&err]) {
			[self showError:err.localizedDescription];
		}
		return;
	}
	[LuaSourceLoader.shared dropCacheForPath:path];
	[self unrequireExceptModel];
	NSString *entry = [LuaSourceLoader.shared entryPath:&err];
	NSData *src = entry ? [LuaSourceLoader.shared dataForPath:entry error:&err] : nil;
	if (!src) {
		[self showError:err.localizedDescription ?: @"reload failed"];
		return;
	}
	NSString *chunk = [NSString stringWithFormat:@"@%@", entry];
	if (luaL_loadbuffer(_L, src.bytes, src.length, chunk.UTF8String) != LUA_OK
		|| lua_pcall(_L, 0, 1, 0) != LUA_OK) {
		[self showError:[self luaError:@"reload"].localizedDescription];
		return;
	}
	if (![self instantiate:&err]) {
		[self showError:err.localizedDescription];
	}
}

@end
