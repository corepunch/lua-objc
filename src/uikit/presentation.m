#pragma mark - UIKit presentation bridge

static UIViewController *lua_uikit_presenter(void) {
	UIWindow *window = lua_objc_host_window();
	UIViewController *presenter = window.rootViewController;
	while (presenter.presentedViewController)
		presenter = presenter.presentedViewController;
	return presenter;
}

static int bridge_UIKitPresentation_presentSheet(lua_State *L) {
	UIViewController *sheet = check_view_controller(L, 1);
	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");

	sheet.modalPresentationStyle = UIModalPresentationPageSheet;
	if (lua_istable(L, 2)) {
		lua_getfield(L, 2, "title");
		if (!lua_isnoneornil(L, -1))
			sheet.title = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
		lua_pop(L, 1);
	}
	[presenter presentViewController:sheet animated:NO completion:nil];
	UISheetPresentationController *presentation = sheet.sheetPresentationController;
	if (presentation && lua_istable(L, 2)) {
		lua_getfield(L, 2, "detents");
		if (lua_istable(L, -1)) {
			NSMutableArray<UISheetPresentationControllerDetent *> *detents =
				[NSMutableArray array];
			for (lua_Integer i = 1; i <= luaL_len(L, -1); i++) {
				lua_rawgeti(L, -1, i);
				const char *name = luaL_checkstring(L, -1);
				if (strcmp(name, "medium") == 0)
					[detents addObject:UISheetPresentationControllerDetent.mediumDetent];
				else if (strcmp(name, "large") == 0)
					[detents addObject:UISheetPresentationControllerDetent.largeDetent];
				lua_pop(L, 1);
			}
			if (detents.count > 0) presentation.detents = detents;
		}
		lua_pop(L, 1);
		presentation.prefersGrabberVisible = YES;
	}
	push_objc(L, sheet, "uiviewcontroller");
	return 1;
}

static int bridge_UIKitPresentation_dismiss(lua_State *L) {
	UIViewController *presenter = lua_uikit_presenter();
	if (presenter.presentedViewController)
		[presenter dismissViewControllerAnimated:NO completion:nil];
	return 0;
}

static int bridge_UIKitPresentation_confirm(lua_State *L) {
	const char *title = luaL_optstring(L, 1, "Confirm");
	const char *message = luaL_optstring(L, 2, "");
	const char *primary = luaL_optstring(L, 3, "OK");
	const char *cancel = luaL_optstring(L, 4, "Cancel");
	int callback = LUA_NOREF;
	if (!lua_isnoneornil(L, 5)) {
		luaL_checktype(L, 5, LUA_TFUNCTION);
		lua_pushvalue(L, 5);
		callback = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");
	UIAlertController *alert = [UIAlertController
		alertControllerWithTitle:[NSString stringWithUTF8String:title]
		message:[NSString stringWithUTF8String:message]
		preferredStyle:UIAlertControllerStyleAlert];
	int callbackRef = callback;
	UIAlertAction *primaryAction = [UIAlertAction
		actionWithTitle:[NSString stringWithUTF8String:primary]
		style:UIAlertActionStyleDestructive
		handler:^(__unused UIAlertAction *action) {
			if (callbackRef == LUA_NOREF || !gL) return;
			lua_rawgeti(gL, LUA_REGISTRYINDEX, callbackRef);
			lua_objc_pcall(gL, 0, 0, "confirm");
			luaL_unref(gL, LUA_REGISTRYINDEX, callbackRef);
		}];
	[alert addAction:primaryAction];
	if (cancel && cancel[0]) {
		[alert addAction:[UIAlertAction
			actionWithTitle:[NSString stringWithUTF8String:cancel]
			style:UIAlertActionStyleCancel handler:nil]];
	}
	[presenter presentViewController:alert animated:NO completion:nil];
	return 0;
}
