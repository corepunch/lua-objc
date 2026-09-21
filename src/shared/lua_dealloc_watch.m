/* lua_dealloc_watch.m — test-only native deallocation observability.
 *
 * Attaches a sentinel associated object to a native view. When the view
 * deallocs, the sentinel deallocs and bumps a process-wide counter exposed
 * through `_deallocCount`. Used by headless regression tests to assert the
 * ownership contract directly:
 *   - an unmounted view deallocs once its last Lua handle is collected;
 *   - a mounted view survives handle collection while its parent retains it;
 *   - it deallocs after window close / scope close plus collection.
 *
 * The sentinel pointer itself is the association key, so watching the same
 * view twice (or watching several views) never overwrites a previous watch.
 */

static int lua_dealloc_count_value = 0;

@interface LuaDeallocSentinel : NSObject
@end

@implementation LuaDeallocSentinel
- (void)dealloc {
	lua_dealloc_count_value++;
}
@end

static int bridge_dealloc_watch(lua_State *L) {
	ObjCRef *ref = lua_objc_test_ref(L, 1);
	if (!ref) return luaL_typeerror(L, 1, "Objective-C object");
	id obj = lua_objc_live_ptr(L, 1, ref);
	if (!obj) return lua_objc_argerror_released(L, 1);
	LuaDeallocSentinel *sentinel = [[LuaDeallocSentinel alloc] init];
	/* Keyed by the sentinel's own address: unique per watch, retained by
	 * the target for exactly the target's lifetime. */
	objc_setAssociatedObject(obj, (__bridge const void *)sentinel, sentinel,
		OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_dealloc_count(lua_State *L) {
	lua_pushinteger(L, (lua_Integer)lua_dealloc_count_value);
	return 1;
}

static int bridge_dealloc_reset(lua_State *L) {
	(void)L;
	lua_dealloc_count_value = 0;
	return 0;
}
