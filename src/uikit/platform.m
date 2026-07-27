#pragma mark - Show

static int bridge_show(lua_State *L) {
	UIWindow *w = (__bridge UIWindow *)((ObjCRef *)lua_touserdata(L, 1))->ptr;
	[w makeKeyAndVisible];
	return 0;
}

#pragma mark - Generic bridge

static int bridge_create(lua_State *L) {
	const char *className = luaL_checkstring(L, 1);
	Class cls = NSClassFromString([NSString stringWithUTF8String:className]);
	if (!cls) return luaL_error(L, "unknown class: %s", className);

	id obj = [[cls alloc] init];
	push_objc(L, obj, [obj isKindOfClass:[UIWindow class]] ? "uiwindow" : "uiview");
	return 1;
}

static int bridge_font(lua_State *L) {
	CGFloat size = luaL_checknumber(L, 1);
	const char *weightStr = luaL_optstring(L, 2, NULL);

	UIFontWeight w = UIFontWeightRegular;
	if (weightStr) {
		if (strcmp(weightStr, "bold") == 0) w = UIFontWeightBold;
		else if (strcmp(weightStr, "semibold") == 0) w = UIFontWeightSemibold;
		else if (strcmp(weightStr, "light") == 0) w = UIFontWeightLight;
		else if (strcmp(weightStr, "heavy") == 0) w = UIFontWeightHeavy;
	}

	UIFont *font = [UIFont systemFontOfSize:size weight:w];
	push_objc(L, font, "nsobject");
	return 1;
}

static int bridge_perform(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *selName = luaL_checkstring(L, 2);
	SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
	if (![obj respondsToSelector:sel]) return 0;

	id arg = nil;
	if (!lua_isnoneornil(L, 3)) {
		arg = lua_to_objc_value(L, 3);
	}

	NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
	if (!sig) return 0;

	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	inv.target = obj;
	inv.selector = sel;
	if (sig.numberOfArguments > 2) {
		[inv setArgument:&arg atIndex:2];
	}
	[inv invoke];

	if (sig.methodReturnLength > 0) {
		const char *retType = sig.methodReturnType;
		if (strcmp(retType, @encode(BOOL)) == 0 || strcmp(retType, "B") == 0 || strcmp(retType, "c") == 0) {
			BOOL val = NO;
			[inv getReturnValue:&val];
			lua_pushboolean(L, val);
		} else if (strcmp(retType, @encode(NSInteger)) == 0 || strcmp(retType, "q") == 0) {
			NSInteger val = 0;
			[inv getReturnValue:&val];
			lua_pushinteger(L, (lua_Integer)val);
		} else if (strcmp(retType, @encode(CGFloat)) == 0 || strcmp(retType, "d") == 0) {
			CGFloat val = 0;
			[inv getReturnValue:&val];
			lua_pushnumber(L, val);
		} else if (strcmp(retType, "@") == 0) {
			__unsafe_unretained id val = nil;
			[inv getReturnValue:&val];
			push_objc_value(L, val);
		} else {
			lua_pushnil(L);
		}
		return 1;
	}
	return 0;
}

static int bridge_callback(lua_State *L) {
	id obj = check_objc(L, 1);
	luaL_checktype(L, 2, LUA_TFUNCTION);
	lua_pushvalue(L, 2);
	int ref = luaL_ref(L, LUA_REGISTRYINDEX);

	objc_setAssociatedObject(obj, &kCallbackKey, @(ref), OBJC_ASSOCIATION_RETAIN);
	if ([obj respondsToSelector:@selector(addTarget:action:forControlEvents:)]) {
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
		forControlEvents:UIControlEventTouchUpInside];
	}

	return 0;
}

