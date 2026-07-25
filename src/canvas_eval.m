/* canvas_eval.m — isolated Lua state evaluation for the IDEKit canvas.
 *
 * Included directly into main.m (same translation unit) so it can access
 * the static symbols gL, ObjCRef, push_objc, luaopen_bridge.
 *
 * Each canvas eval runs in a brand-new lua_State that is torn down when
 * the eval completes, giving complete isolation from the main state:
 *   - globals set by user code do not leak between runs
 *   - package.loaded / module cache is not shared
 *   - registry refs (callbacks, timers) from previous runs cannot fire
 */

int luaopen_bridge(lua_State *L);  /* defined later in main.m */

#pragma mark - eval & canvas

NSTextView *text_view_from_scroll_view(NSView *obj) {
	if (![obj isKindOfClass:[NSScrollView class]]) return nil;
	NSTextView *tv = (NSTextView *)((NSScrollView *)obj).documentView;
	if (![tv isKindOfClass:[NSTextView class]]) return nil;
	return tv;
}

/* Create a fully-initialised, isolated lua_State for one canvas eval.
 * Inherits package.path from gL so require('AppKit') etc. resolve correctly.
 * The caller owns the returned state and must lua_close() it when done. */
static lua_State *canvas_state_create(void) {
	lua_State *C = luaL_newstate();
	if (!C) return NULL;
	luaL_openlibs(C);

	/* Store itself as bridge_main so any async bridge callbacks that
	 * fire while the canvas is being built land on the right state.
	 * (Canvas eval is synchronous, so this is defensive.) */
	lua_pushlightuserdata(C, C);
	lua_setfield(C, LUA_REGISTRYINDEX, "bridge_main");

	luaL_requiref(C, "bridge", luaopen_bridge, 1);
	lua_pop(C, 1);

	/* Copy package.path from gL so all Lua modules resolve identically. */
	lua_getglobal(gL, "package");
	lua_getfield(gL, -1, "path");
	const char *path = lua_tostring(gL, -1);
	if (path) {
		lua_getglobal(C, "package");
		lua_pushstring(C, path);
		lua_setfield(C, -2, "path");
		lua_pop(C, 1);
	}
	lua_pop(gL, 2);

	return C;
}

static int bridge_eval(lua_State *L) {
	const char *code = luaL_checkstring(L, 1);
	int canvas = lua_toboolean(L, 2);

	char wrapped[65536];
	int n;

	if (canvas) {
		/* Canvas mode: run in a fresh, isolated lua_State so user code
		 * cannot pollute globals, module cache, or registry of the main
		 * state.  ns.Window / ns.Preview are intercepted to return a
		 * VStack instead of a real NSWindow. */
		lua_State *C = canvas_state_create();
		if (!C) {
			lua_pushnil(L);
			lua_pushstring(L, "failed to create canvas state");
			return 2;
		}

		n = snprintf(wrapped, sizeof(wrapped),
			"local ns=require('AppKit');"
			"local __rr;"
			"ns.Window=function(p) __rr=ns.VStack(p) return __rr end;"
			"ns.Preview=function(p) __rr=ns.VStack(p) return __rr end;"
			"local __rok,__ret=pcall(function()\n%s\nend);"
			"if not __rok then error(__ret) end;"
			"return __ret or __rr",
			code);

		if (n < 0 || n >= (int)sizeof(wrapped)) {
			lua_close(C);
			lua_pushnil(L);
			lua_pushstring(L, "code too long");
			return 2;
		}

		if (luaL_loadstring(C, wrapped) != LUA_OK) {
			const char *err = lua_tostring(C, -1);
			lua_pushnil(L);
			lua_pushstring(L, err ?: "compile error");
			lua_close(C);
			return 2;
		}

		if (lua_pcall(C, 0, 1, 0) != LUA_OK) {
			const char *err = lua_tostring(C, -1);
			lua_pushnil(L);
			lua_pushstring(L, err ?: "runtime error");
			lua_close(C);
			return 2;
		}

		/* Marshal the resulting view from the canvas state into gL.
		 * The ObjCRef holds a CFBridgingRetain'd pointer, so extracting
		 * the id and re-retaining it in gL is safe across lua_close(C). */
		id resultObj = nil;
		ObjCRef *ref = luaL_testudata(C, -1, "nsview");
		if (!ref) ref = luaL_testudata(C, -1, "nswindow");
		if (ref) resultObj = (__bridge id)ref->ptr;

		if (resultObj) {
			push_objc(L, resultObj, "nsview");
		} else {
			lua_pushnil(L);
		}
		lua_close(C);
		lua_pushnil(L);  /* no error */
		return 2;
	} else {
		n = snprintf(wrapped, sizeof(wrapped),
			"local ns=require('AppKit');return(function()\n%s\nend)()",
			code);
	}

	if (n < 0 || n >= (int)sizeof(wrapped)) {
		lua_pushnil(L);
		lua_pushstring(L, "code too long");
		return 2;
	}

	if (luaL_loadstring(L, wrapped) != LUA_OK) {
		lua_pushnil(L);
		lua_insert(L, -2);
		return 2;
	}

	if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
		lua_pushnil(L);
		lua_insert(L, -2);
		return 2;
	}

	lua_pushnil(L);
	return 2;
}

static int bridge_clear_container(lua_State *L) {
	NSView *container = check_view(L, 1);
	for (NSView *sub in [container.subviews copy]) {
		[sub removeFromSuperview];
	}
	layout_recursive(container, container.bounds.size.width);
	return 0;
}
