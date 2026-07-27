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
 *
 * CANCELLATION
 * When the user saves new code, _evalIntoCanvas calls bridge._eval again.
 * gLastCanvasOwner tracks the most-recently-created canvas owner so that
 * bridge_eval can call [owner cancel] before spinning up the new state.
 * This immediately cancels all in-flight NSURLSessionDataTasks and NSTimers
 * from the previous eval, preventing orphaned coroutines from resuming
 * into stale views.
 */

/* Strong ref to the canvas owner currently running async work.
 * Cancelled and replaced each time bridge_eval creates a new canvas state. */
static LuaStateOwner *gLastCanvasOwner = nil;

int luaopen_bridge(lua_State *L);  /* defined later in main.m */

#pragma mark - eval & canvas

/* Lua registry refs stored on a bridged ObjC object via associated objects
 * point at the canvas state's registry.  Those refs are invalid in the main
 * state, and the canvas state may be closed at any time.  Strip them
 * recursively before the view crosses the state boundary so stale lookups
 * produce nil instead of crashing or calling the wrong function. */
static void clear_canvas_lua_refs(NSView *view) {
	if (!view) return;

	/* Keys that store Lua registry refs (NSNumber wrapping an int ref).
	 * Do NOT touch keys that store pure ObjC objects such as layout metadata
	 * (kAxisKey, kFlexibleKey, etc.) or table data sources. */
	static const void * const luaRefKeys[] = {
		&kKeys[kCallbackKey],
		&kKeys[kTableRefreshKey],
		&kKeys[kTableSelectionKey],
		&kKeys[kTextChangeKey],
	};
	static const int luaRefKeyCount =
		(int)(sizeof(luaRefKeys) / sizeof(luaRefKeys[0]));

	for (int i = 0; i < luaRefKeyCount; i++) {
		objc_setAssociatedObject(view, luaRefKeys[i], nil,
			OBJC_ASSOCIATION_RETAIN);
	}

	for (NSView *sub in view.subviews) {
		clear_canvas_lua_refs(sub);
	}
}

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

	/* Zero the extraspace so owner_for_state() returns nil until an
	 * owner is attached.  bridge_eval attaches one immediately; the
	 * --preview path runs without one, and async callbacks from a
	 * preview script are dropped instead of crashing after lua_close. */
	*(void **)lua_getextraspace(C) = NULL;

	luaL_requiref(C, "AppKitNative", luaopen_bridge, 1);
	lua_pop(C, 1);
	luaL_requiref(C, "bridge", luaopen_bridge, 1);
	lua_pop(C, 1);

	/* Copy both Lua and native module paths so isolated previews resolve the
	 * same embedded framework dylibs as the main application state. */
	lua_getglobal(gL, "package");
	lua_getglobal(C, "package");
	const char *fields[] = { "path", "cpath" };
	for (int i = 0; i < 2; i++) {
		lua_getfield(gL, -1, fields[i]);
		const char *value = lua_tostring(gL, -1);
		if (value) {
			lua_pushstring(C, value);
			lua_setfield(C, -2, fields[i]);
		}
		lua_pop(gL, 1);
	}
	lua_pop(C, 1);
	lua_pop(gL, 1);

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
		/* Cancel any in-flight async work (fetches, timers) from the previous
		 * canvas eval before creating the new state.  This prevents orphaned
		 * coroutines from resuming into stale views after a re-eval. */
		[gLastCanvasOwner cancel];
		gLastCanvasOwner = nil;

		lua_State *C = canvas_state_create();
		if (!C) {
			fprintf(stderr, "canvas error: failed to create canvas state\n");
			fflush(stderr);
			lua_pushnil(L);
			lua_pushstring(L, "failed to create canvas state");
			return 2;
		}
		LuaStateOwner *canvasOwner = [[LuaStateOwner alloc] initWithState:C];
		gLastCanvasOwner = canvasOwner;  /* track for cancellation on next eval */

		n = snprintf(wrapped, sizeof(wrapped),
			"local ns=require('AppKit');"
			"local __rr, __tvbar;"
			"ns.Window=function(p) __tvbar=p.toolbar; __rr=ns.VStack(p) return __rr end;"
			"ns.Preview=function(p) __rr=ns.VStack(p) return __rr end;"
			"local __rok,__ret=pcall(function()\n%s\nend);"
			"if not __rok then error(__ret) end;"
			"return __ret or __rr, __tvbar",
			code);

		if (n < 0 || n >= (int)sizeof(wrapped)) {
			fprintf(stderr, "canvas error: code too long\n");
			fflush(stderr);
			lua_pushnil(L);
			lua_pushstring(L, "code too long");
			return 2;
		}

		if (luaL_loadstring(C, wrapped) != LUA_OK) {
			const char *err = lua_tostring(C, -1);
			report_lua_error(C, "canvas");
			lua_pushnil(L);
			lua_pushstring(L, err ?: "compile error");
			return 2;
		}

		if (lua_pcall(C, 0, 2, 0) != LUA_OK) {
			const char *err = lua_tostring(C, -1);
			report_lua_error(C, "canvas");
			lua_pushnil(L);
			lua_pushstring(L, err ?: "runtime error");
			return 2;
		}

		/* Stack (C): [-2] = content view, [-1] = toolbar items table (or nil) */

		/* Extract toolbar item definitions and store on the content view
		 * as an NSArray of NSDictionary so _evalIntoCanvas can build
		 * native buttons for the CANVAS ControlBar in the main state. */
		{
			ObjCRef *cvref = luaL_testudata(C, -2, "nsview");
			if (!cvref) cvref = luaL_testudata(C, -2, "nswindow");
			NSView *contentView = cvref ? (__bridge NSView *)cvref->ptr : nil;

			if (contentView && lua_istable(C, -1)) {
				NSMutableArray *items = [NSMutableArray array];

				lua_pushnil(C);
				while (lua_next(C, -2)) {
					/* key: index, value: item table {icon, label, tooltip} */
					if (lua_istable(C, -1)) {
						NSMutableDictionary *dict = [NSMutableDictionary dictionary];
						lua_pushnil(C);
						while (lua_next(C, -2)) {
							const char *k = lua_tostring(C, -2);
							const char *v = lua_tostring(C, -1);
							if (k && v) dict[@(k)] = @(v);
							lua_pop(C, 1);
						}
						if (dict.count > 0) [items addObject:dict];
					}
					lua_pop(C, 1);
				}

				objc_setAssociatedObject(contentView,
					&kKeys[kCanvasToolbarItemsKey], items,
					OBJC_ASSOCIATION_RETAIN);
			}
		}
		lua_pop(C, 1);  /* pop toolbar items */

		/* Marshal the resulting view from the canvas state into gL.
		 * The ObjCRef holds a CFBridgingRetain'd pointer, so extracting
		 * the id and re-retaining it in gL is safe.  ARC manages C's
		 * lifetime via LuaStateOwner: our local reference is released
		 * at return; the state stays alive only while async callbacks
		 * hold a reference, and closes automatically when they finish. */
		id resultObj = nil;
		ObjCRef *ref = luaL_testudata(C, -1, "nsview");
		if (!ref) ref = luaL_testudata(C, -1, "nswindow");
		if (ref) resultObj = (__bridge id)ref->ptr;

		if (resultObj) {
			if ([resultObj isKindOfClass:[NSView class]]) {
				clear_canvas_lua_refs((NSView *)resultObj);
			}
			push_objc(L, resultObj, "nsview");
		} else {
			lua_pushnil(L);
		}
		lua_pushnil(L);  /* no error */
		return 2;
	} else {
		n = snprintf(wrapped, sizeof(wrapped),
			"local ns=require('AppKit');return(function()\n%s\nend)()",
			code);
	}

	if (n < 0 || n >= (int)sizeof(wrapped)) {
		fprintf(stderr, "eval error: code too long\n");
		fflush(stderr);
		lua_pushnil(L);
		lua_pushstring(L, "code too long");
		return 2;
	}

	if (luaL_loadstring(L, wrapped) != LUA_OK) {
		report_lua_error(L, "eval");
		lua_pushnil(L);
		lua_insert(L, -2);
		return 2;
	}

	if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
		report_lua_error(L, "eval");
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
