#pragma mark - UIKit presentation bridge

static UIViewController *lua_uikit_presenter(void) {
	UIWindow *window = LRTApplicationWindow();
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
	[presenter presentViewController:sheet animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
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
		lua_getfield(L, 2, "dragIndicator");
		if (lua_isboolean(L, -1))
			presentation.prefersGrabberVisible = lua_toboolean(L, -1);
		else if (lua_isstring(L, -1))
			presentation.prefersGrabberVisible = strcmp(lua_tostring(L, -1), "hidden") != 0;
		else
			presentation.prefersGrabberVisible = YES;
		lua_pop(L, 1);
	}
	push_objc(L, sheet, "uiviewcontroller");
	return 1;
}

static int bridge_UIKitPresentation_dismiss(lua_State *L) {
	UIViewController *presenter = lua_uikit_presenter();
	if (presenter.presentingViewController)
		[presenter dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
	return 0;
}

static int bridge_UIKitPresentation_confirm(lua_State *L) {
	const char *title = luaL_optstring(L, 1, "Confirm");
	const char *message = luaL_optstring(L, 2, "");
	const char *primary = luaL_optstring(L, 3, "OK");
	const char *cancel = luaL_optstring(L, 4, "Cancel");
	LuaReg *callback = lua_reg_opt(L, 5);

	UIViewController *presenter = lua_uikit_presenter();
	if (!presenter) return luaL_error(L, "no UIKit presenter is installed");
	UIAlertController *alert = [UIAlertController
		alertControllerWithTitle:[NSString stringWithUTF8String:title]
		message:[NSString stringWithUTF8String:message]
		preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *primaryAction = [UIAlertAction
		actionWithTitle:[NSString stringWithUTF8String:primary]
		style:UIAlertActionStyleDestructive
		handler:^(__unused UIAlertAction *action) {
			lua_State *callL = lua_reg_live_state(callback);
			if (callL && lua_reg_push(callback))
				lua_objc_pcall(callL, 0, 0, "confirm");
			[callback dispose];
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
