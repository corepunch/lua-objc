/* Native constructors exported by the UIKit module. */

static int bridge_UIKitControls_vstack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_hstack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_hsplit(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"hsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_spacer(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_textField(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	UITextField *obj = [[UITextField alloc] initWithFrame:CGRectZero];
	obj.text = [NSString stringWithUTF8String:text];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_label(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	UILabel *obj = [[UILabel alloc] initWithFrame:CGRectZero];
	obj.text = [NSString stringWithUTF8String:text];
	obj.numberOfLines = 0;
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_separator(lua_State *L) {
	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kFixedHeightKey, @1,
		OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES,
		OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_progressIndicator(lua_State *L) {
	UIActivityIndicatorView *obj =
		[[UIActivityIndicatorView alloc] initWithFrame:CGRectZero];
	[obj startAnimating];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	BOOL has_callback = !lua_isnoneornil(L, 2);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIButton *obj = [UIButton buttonWithType:UIButtonTypeSystem];
	[obj setTitle:[NSString stringWithUTF8String:title] forState:UIControlStateNormal];
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:) forControlEvents:UIControlEventTouchUpInside];
	}
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	BOOL has_callback = !lua_isnoneornil(L, 3);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UISwitch *obj = [[UISwitch alloc] initWithFrame:CGRectZero];
	obj.on = is_on;
	obj.accessibilityLabel = [NSString stringWithUTF8String:label];
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:) forControlEvents:UIControlEventValueChanged];
	}
	push_objc(L, obj, "uiview");
	return 1;
}
