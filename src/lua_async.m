/* lua_async.m — Lua async bridge: LuaStateOwner, HTTP, timer, JSON.
 *
 * Included directly into main.m (same translation unit).
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
 * The owner is the *only* ARC strong reference to the lua_State.
 * Async blocks (HTTP completion, timer block) capture the owner
 * strongly, keeping the state alive until outstanding work drains.
 * The last release calls -dealloc → lua_close on the main thread.
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

#pragma mark - LuaStateOwner

@interface LuaStateOwner : NSObject
@property (nonatomic, readonly) lua_State *L;
@property (nonatomic, readonly) BOOL cancelled;
- (void)cancel;
- (void)trackTask:(NSURLSessionDataTask *)task;
- (void)trackTimer:(NSTimer *)timer;
@end

@implementation LuaStateOwner {
    NSMutableArray *_pending;   /* NSURLSessionDataTask | NSTimer */
}

- (instancetype)initWithState:(lua_State *)L {
    self = [super init];
    _L = L;
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
    if (!L) return;
    if ([NSThread isMainThread]) {
        lua_close(L);
    } else {
        /* lua_close runs __gc handlers that CFRelease NSViews; AppKit
         * requires view dealloc on the main thread. */
        dispatch_async(dispatch_get_main_queue(), ^{
            lua_close(L);
        });
    }
}

@end

/* Resolve the owner from any thread of a global state (main or
 * coroutine).  Returns nil for states without an owner (preview canvas),
 * which callers treat as "drop the callback silently". */
static inline LuaStateOwner *owner_for_state(lua_State *L) {
    return (__bridge LuaStateOwner *)(*(void **)lua_getextraspace(L));
}

#pragma mark - Timer

static int bridge_timer_after(lua_State *L) {
    double delay = luaL_checknumber(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    /* L may be a coroutine; extraspace inherits from the main thread. */
    LuaStateOwner *owner = owner_for_state(L);

    /* __block so the block can untrack itself after firing. */
    __block NSTimer *timer = [NSTimer
        scheduledTimerWithTimeInterval:delay
        repeats:NO
        block:^(NSTimer *t) {
            [owner _untrack:timer];
            if (!owner || owner.cancelled) {
                luaL_unref(owner.L, LUA_REGISTRYINDEX, ref);
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
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    /* L may be a coroutine; extraspace inherits from the main thread. */
    LuaStateOwner *owner = owner_for_state(L);

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]];
    [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        @"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        forHTTPHeaderField:@"User-Agent"];

    /* __block so the completion block can untrack itself by name. */
    __block NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
            if (!owner) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [owner _untrack:task];
                if (owner.cancelled) {
                    luaL_unref(owner.L, LUA_REGISTRYINDEX, ref);
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
