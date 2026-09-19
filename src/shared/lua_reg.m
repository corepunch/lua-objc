/* lua_reg.m — state-bound Lua callback registrations.
 *
 * A LuaReg roots one registry value (usually a closure) against the
 * originating LuaStateOwner. Native targets retain the registration via
 * associated objects; a Lua Scope may also hold it and dispose it on
 * unmount. dispose is idempotent. Registrations never use a process-global
 * lua_State pointer.
 */

static const char *kLuaRegMeta = "lua_objc.reg";
static const char *kCurrentScopeKey = "lua_objc.current_scope";

@interface LuaReg : NSObject
@property (nonatomic, readonly) int ref;
@property (nonatomic, readonly, weak) LuaStateOwner *owner;
+ (instancetype)regWithRef:(int)ref owner:(LuaStateOwner *)owner;
- (void)dispose;
@end

@implementation LuaReg {
	int _ref;
	__weak LuaStateOwner *_owner;
}

+ (instancetype)regWithRef:(int)ref owner:(LuaStateOwner *)owner {
	LuaReg *reg = [[self alloc] init];
	reg->_ref = ref;
	reg->_owner = owner;
	return reg;
}

- (int)ref {
	return _ref;
}

- (LuaStateOwner *)owner {
	return _owner;
}

- (void)dispose {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self dispose]; });
		return;
	}
	int r = _ref;
	LuaStateOwner *o = _owner;
	_ref = LUA_NOREF;
	_owner = nil;
	if (r == LUA_NOREF) return;
	if (o && o.L && !o.closing)
		luaL_unref(o.L, LUA_REGISTRYINDEX, r);
}

- (void)dealloc {
	int r = _ref;
	LuaStateOwner *o = _owner;
	_ref = LUA_NOREF;
	_owner = nil;
	if (r == LUA_NOREF) return;
	if (!o || !o.L || o.closing) return;
	if ([NSThread isMainThread]) {
		luaL_unref(o.L, LUA_REGISTRYINDEX, r);
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (o.L && !o.closing)
				luaL_unref(o.L, LUA_REGISTRYINDEX, r);
		});
	}
}

@end

typedef struct {
	void *ptr;
} LuaRegRef;

static void push_luareg(lua_State *L, LuaReg *reg) {
	if (!reg) {
		lua_pushnil(L);
		return;
	}
	LuaRegRef *ud = lua_newuserdata(L, sizeof(LuaRegRef));
	ud->ptr = (void *)CFBridgingRetain(reg);
	luaL_setmetatable(L, kLuaRegMeta);
}

static LuaReg *luareg_from_stack(lua_State *L, int idx) {
	LuaRegRef *ud = luaL_testudata(L, idx, kLuaRegMeta);
	if (!ud || !ud->ptr) return nil;
	return (__bridge LuaReg *)ud->ptr;
}

static int luareg_dispose(lua_State *L) {
	LuaReg *reg = luareg_from_stack(L, 1);
	if (!reg) luaL_checkudata(L, 1, kLuaRegMeta);
	[reg dispose];
	return 0;
}

static int luareg_gc(lua_State *L) {
	LuaRegRef *ud = lua_touserdata(L, 1);
	if (ud && ud->ptr) {
		CFRelease(ud->ptr);
		ud->ptr = NULL;
	}
	return 0;
}

static void register_luareg_metatable(lua_State *L) {
	if (!luaL_newmetatable(L, kLuaRegMeta)) {
		lua_pop(L, 1);
		return;
	}
	lua_newtable(L);
	lua_pushcfunction(L, luareg_dispose);
	lua_setfield(L, -2, "dispose");
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, luareg_gc);
	lua_setfield(L, -2, "__gc");
	lua_pop(L, 1);
}

static void lua_reg_bind_current_scope(lua_State *L, LuaReg *reg) {
	lua_getfield(L, LUA_REGISTRYINDEX, kCurrentScopeKey);
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return;
	}
	lua_getfield(L, -1, "add");
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 2);
		return;
	}
	lua_insert(L, -2);
	push_luareg(L, reg);
	if (lua_pcall(L, 2, 0, 0) != LUA_OK)
		report_lua_error(L, "scope add");
}

static LuaReg *lua_reg_create(lua_State *L, int idx, BOOL bindScope) {
	luaL_checktype(L, idx, LUA_TFUNCTION);
	LuaStateOwner *owner = owner_for_state(L);
	lua_pushvalue(L, idx);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);
	LuaReg *reg = [LuaReg regWithRef:ref owner:owner];
	if (bindScope) lua_reg_bind_current_scope(L, reg);
	return reg;
}

static LuaReg *lua_reg_opt(lua_State *L, int idx) {
	if (lua_isnoneornil(L, idx)) return nil;
	return lua_reg_create(L, idx, YES);
}

__attribute__((unused))
static LuaReg *lua_reg_opt_unscoped(lua_State *L, int idx) {
	if (lua_isnoneornil(L, idx)) return nil;
	return lua_reg_create(L, idx, NO);
}

static void lua_reg_store(id target, const void *key, LuaReg *reg) {
	LuaReg *previous = objc_getAssociatedObject(target, key);
	[previous dispose];
	objc_setAssociatedObject(target, key, reg,
		reg ? OBJC_ASSOCIATION_RETAIN : OBJC_ASSOCIATION_ASSIGN);
}

static lua_State *lua_reg_live_state(LuaReg *reg) {
	if (!reg || reg.ref == LUA_NOREF) return NULL;
	LuaStateOwner *owner = reg.owner;
	if (!owner || !owner.L || owner.closing) return NULL;
	return owner.L;
}

static BOOL lua_reg_push(LuaReg *reg) {
	lua_State *L = lua_reg_live_state(reg);
	if (!L) return NO;
	lua_rawgeti(L, LUA_REGISTRYINDEX, reg.ref);
	return YES;
}

static int bridge_set_current_scope(lua_State *L) {
	if (lua_isnoneornil(L, 1)) {
		lua_pushnil(L);
	} else {
		luaL_checktype(L, 1, LUA_TTABLE);
		lua_pushvalue(L, 1);
	}
	lua_setfield(L, LUA_REGISTRYINDEX, kCurrentScopeKey);
	return 0;
}
