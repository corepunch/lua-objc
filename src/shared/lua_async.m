/* lua_async.m — shared Lua async bridge: state ownership, HTTP, timer, JSON.
 *
 * Included directly into the AppKit and UIKit runtime translation units.
 *
 * LIFETIME MODEL
 * ==============
 * Each lua_State gets exactly one LuaStateOwner stored unretained in
 * lua_getextraspace(L).  LUA_EXTRASPACE is sizeof(void*) — one slot —
 * which the owner pointer occupies fully.
 *
 * Lua copies the main thread's extraspace into every coroutine at
 * lua_newthread time, so owner_for_state(co) resolves the same owner
 * from any coroutine thread with no registry lookup.
 *
 * For runtime-created states, the owner is the only ARC strong reference to
 * the lua_State and closes it at the end of its lifetime. A framework loaded
 * into an external host, such as UIKit.dylib, uses a non-closing owner: the
 * host still owns the state, while callbacks use the same cancellation and
 * coroutine-resolution machinery.
 * Async blocks (HTTP completion, timer block) capture the owner
 * strongly, keeping the state alive until outstanding work drains.
 * For closing owners, the last release calls -dealloc → lua_close on the main
 * thread. Non-closing owners only cancel and release their pending work.
 *
 * CANCELLATION MODEL
 * ==================
 * When a canvas is re-evaluated, the old canvas owner is cancelled:
 *   [owner cancel]
 * This sets owner.cancelled = YES, calls -cancel on all pending
 * NSURLSessionDataTasks, and invalidates all pending NSTimers.
 * Subsequent async callbacks check owner.cancelled and drop silently,
 * so orphaned coroutines from a stale eval never resume.
 *
 * Per-coroutine flags are intentionally absent: LUA_EXTRASPACE holds
 * exactly one pointer (the shared owner), and cancellation is always
 * per-state, not per-coroutine.  Any coroutine running in the state
 * reads the same owner.cancelled flag via owner_for_state(L).
 */

static void report_lua_error(lua_State *L, const char *context);

#ifndef LUA_OBJC_HTTP_USER_AGENT
#define LUA_OBJC_HTTP_USER_AGENT @"lua-objc/1.0"
#endif

#pragma mark - LuaStateOwner

@interface LuaStateOwner : NSObject
@property (nonatomic, readonly) lua_State *L;
@property (nonatomic, readonly) BOOL cancelled;
- (instancetype)initWithState:(lua_State *)L;
- (instancetype)initWithState:(lua_State *)L closesState:(BOOL)closesState;
- (void)cancel;
- (void)detachState;
- (void)trackTask:(NSURLSessionDataTask *)task;
- (void)trackTimer:(NSTimer *)timer;
@end

@implementation LuaStateOwner {
	NSMutableArray *_pending;   /* NSURLSessionDataTask | NSTimer */
	BOOL _closesState;
}

- (instancetype)initWithState:(lua_State *)L {
	return [self initWithState:L closesState:YES];
}

- (instancetype)initWithState:(lua_State *)L closesState:(BOOL)closesState {
	self = [super init];
	_L = L;
	_closesState = closesState;
	_pending = [NSMutableArray array];
	/* Store unretained so coroutines can resolve the owner via extraspace
	 * without creating a retain cycle.  The owner's lifetime is managed
	 * by whoever created it (a local ARC variable), not by the state. */
	*(void **)lua_getextraspace(L) = (__bridge void *)self;
	return self;
}

- (void)cancel {
	if (_cancelled) return;
	_cancelled = YES;
	for (id item in _pending) {
		if ([item isKindOfClass:[NSURLSessionDataTask class]]) {
			[(NSURLSessionDataTask *)item cancel];
		} else if ([item isKindOfClass:[NSTimer class]]) {
			[(NSTimer *)item invalidate];
		}
	}
	[_pending removeAllObjects];
}

- (void)detachState {
	[self cancel];
	_L = NULL;
}

- (void)trackTask:(NSURLSessionDataTask *)task {
	if (_cancelled) { [task cancel]; return; }
	[_pending addObject:task];
}

- (void)trackTimer:(NSTimer *)timer {
	if (_cancelled) { [timer invalidate]; return; }
	[_pending addObject:timer];
}

- (void)_untrack:(id)item {
	[_pending removeObjectIdenticalTo:item];
}

- (void)dealloc {
	lua_State *L = _L;
	if (!L || !_closesState) return;
	if ([NSThread isMainThread]) {
		lua_close(L);
	} else {
		/* lua_close runs __gc handlers that release native views; both AppKit
		 * and UIKit require view deallocation on the main thread. */
		dispatch_async(dispatch_get_main_queue(), ^{
			lua_close(L);
		});
	}
}

@end

/* Resolve the owner from any thread of a global state (main or coroutine).
 * Async bridge functions reject states whose runtime did not install one. */
static inline LuaStateOwner *owner_for_state(lua_State *L) {
	return (__bridge LuaStateOwner *)(*(void **)lua_getextraspace(L));
}

#ifdef LUA_OBJC_EXTERNAL_STATE_OWNER

typedef struct {
	void *ptr;
} LuaStateOwnerRef;

static int gc_external_lua_state_owner(lua_State *L) {
	LuaStateOwnerRef *ref = lua_touserdata(L, 1);
	if (!ref || !ref->ptr) return 0;

	LuaStateOwner *owner = (__bridge LuaStateOwner *)ref->ptr;
	if (owner_for_state(L) == owner) {
		*(void **)lua_getextraspace(L) = NULL;
	}
	[owner detachState];
	CFRelease(ref->ptr);
	ref->ptr = NULL;
	return 0;
}

/* External framework hosts own lua_close(). A registry userdata retains the
 * non-closing owner for exactly the lifetime of that state and detaches it
 * before lua_close releases native userdata. */
static void install_external_lua_state_owner(lua_State *L) {
	LuaStateOwner *owner = [[LuaStateOwner alloc] initWithState:L closesState:NO];
	LuaStateOwnerRef *ref = lua_newuserdata(L, sizeof(LuaStateOwnerRef));
	ref->ptr = (void *)CFBridgingRetain(owner);

	if (luaL_newmetatable(L, "lua_objc.async_owner")) {
		lua_pushcfunction(L, gc_external_lua_state_owner);
		lua_setfield(L, -2, "__gc");
	}
	lua_setmetatable(L, -2);
	lua_setfield(L, LUA_REGISTRYINDEX, "lua_objc.async_owner");
}

#endif

#pragma mark - Timer

static int bridge_timer_after(lua_State *L) {
	double delay = luaL_checknumber(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);

	/* A runtime must install an owner before exposing async bridge calls. */
	LuaStateOwner *owner = owner_for_state(L);
	if (!owner) return luaL_error(L, "async runtime is not initialized");

	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	/* __block so the block can untrack itself after firing. */
	__block NSTimer *timer = [NSTimer
		scheduledTimerWithTimeInterval:delay
		repeats:NO
		block:^(NSTimer *t) {
			[owner _untrack:timer];
			if (owner.cancelled) {
				if (owner.L) luaL_unref(owner.L, LUA_REGISTRYINDEX, ref);
				return;
			}
			lua_State *callL = owner.L;
			lua_rawgeti(callL, LUA_REGISTRYINDEX, ref);
			if (lua_pcall(callL, 0, 0, 0) != LUA_OK) {
				report_lua_error(callL, "timer");
				lua_pop(callL, 1);
			}
			luaL_unref(callL, LUA_REGISTRYINDEX, ref);
		}];

	[owner trackTimer:timer];
	return 0;
}

#pragma mark - HTTP & JSON

static int bridge_http_get(lua_State *L) {
	const char *url = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);

	/* L may be a coroutine; extraspace inherits from the main thread. */
	LuaStateOwner *owner = owner_for_state(L);
	if (!owner) return luaL_error(L, "async runtime is not initialized");

	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	NSMutableURLRequest *req = [NSMutableURLRequest
		requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]];
	[req setValue:LUA_OBJC_HTTP_USER_AGENT forHTTPHeaderField:@"User-Agent"];

	/* __block so the completion block can untrack itself by name. */
	__block NSURLSessionDataTask *task = [[NSURLSession sharedSession]
		dataTaskWithRequest:req
		completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[owner _untrack:task];
				if (owner.cancelled) {
					if (owner.L) luaL_unref(owner.L, LUA_REGISTRYINDEX, ref);
					return;
				}
				lua_State *callL = owner.L;
				lua_rawgeti(callL, LUA_REGISTRYINDEX, ref);
				if (error) {
					lua_pushnil(callL);
					lua_pushstring(callL, error.localizedDescription.UTF8String);
				} else {
					NSString *body = [[NSString alloc] initWithData:data
						encoding:NSUTF8StringEncoding];
					lua_pushstring(callL, body.UTF8String ?: "");
					lua_pushnil(callL);
				}
				if (lua_pcall(callL, 2, 0, 0) != LUA_OK) {
					report_lua_error(callL, "http");
					lua_pop(callL, 1);
				}
				luaL_unref(callL, LUA_REGISTRYINDEX, ref);
			});
		}];

	[owner trackTask:task];
	[task resume];
	return 0;
}

static void push_foundation_value(lua_State *L, id value) {
	if (!value || value == [NSNull null]) {
		lua_pushnil(L);
	} else if ([value isKindOfClass:[NSString class]]) {
		lua_pushstring(L, [(NSString *)value UTF8String]);
	} else if ([value isKindOfClass:[NSNumber class]]) {
		NSNumber *num = (NSNumber *)value;
		if (strcmp(num.objCType, @encode(BOOL)) == 0
			|| strcmp(num.objCType, "c") == 0
			|| strcmp(num.objCType, "B") == 0) {
			lua_pushboolean(L, num.boolValue);
		} else {
			lua_pushnumber(L, num.doubleValue);
		}
	} else if ([value isKindOfClass:[NSDictionary class]]) {
		lua_newtable(L);
		NSDictionary *dict = (NSDictionary *)value;
		for (id key in dict) {
			push_foundation_value(L, dict[key]);
			NSString *strKey = [key isKindOfClass:[NSString class]]
				? (NSString *)key : [key description];
			lua_setfield(L, -2, strKey.UTF8String);
		}
	} else if ([value isKindOfClass:[NSArray class]]) {
		lua_newtable(L);
		NSArray *array = (NSArray *)value;
		int i = 1;
		for (id item in array) {
			push_foundation_value(L, item);
			lua_rawseti(L, -2, i++);
		}
	} else {
		lua_pushstring(L, [[value description] UTF8String]);
	}
}

static int bridge_json_parse(lua_State *L) {
	const char *json = luaL_checkstring(L, 1);
	NSData *data = [[NSString stringWithUTF8String:json]
		dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (error) {
		lua_pushnil(L);
		lua_pushstring(L, error.localizedDescription.UTF8String);
		return 2;
	}
	push_foundation_value(L, obj);
	return 1;
}
