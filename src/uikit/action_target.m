#pragma mark - LuaButtonTarget

@interface LuaButtonTarget : NSObject
+ (instancetype)shared;
@end

@implementation LuaButtonTarget

+ (instancetype)shared {
	static LuaButtonTarget *instance = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ instance = [[self alloc] init]; });
	return instance;
}

- (void)onAction:(id)sender {
	LuaReg *reg = objc_getAssociatedObject(sender, &kCallbackKey);
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return;
	lua_objc_pcall(L, 0, 0, "button");
}

@end

static int bridge_invoke_action(lua_State *L) {
	ObjCRef *ref = lua_objc_test_ref(L, 1);
	if (!ref) return luaL_typeerror(L, 1, "uiview");
	id obj = lua_objc_live_ptr(L, 1, ref);
	[[LuaButtonTarget shared] onAction:obj];
	return 0;
}
