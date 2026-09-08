// Lua cannot complete AppKit layout or convert between flipped coordinate
// systems through KVC. Measure native bounds in the actual root's coordinates.
static int bridge_parity_measure(lua_State *L) {
	@autoreleasepool {
		NSView *root = check_view(L, 1);
		root.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
		root.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirectionLeftToRight;
		luaL_checktype(L, 2, LUA_TTABLE);
		NSMutableDictionary *result = [lua_to_objc_value(L, 3) mutableCopy];
		CGFloat width = [result[@"width"] doubleValue], height = [result[@"height"] doubleValue];
		root.frame = NSMakeRect(0, 0, width, height);
		root.bounds = NSMakeRect(0, 0, width, height);
		[root layoutSubtreeIfNeeded];
		layout_recursive(root, width);
		[root layoutSubtreeIfNeeded];
		NSMutableArray *probes = [NSMutableArray array];
		for (lua_Integer i = 1; i <= (lua_Integer)lua_rawlen(L, 2); i++) {
			lua_rawgeti(L, 2, i);
			lua_getfield(L, -1, "id");
			NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, -1)];
			lua_pop(L, 1);
			lua_getfield(L, -1, "view");
			NSView *view = check_view(L, -1);
			NSRect rect = [view convertRect:view.bounds toView:root];
			CGFloat y = root.isFlipped ? NSMinY(rect) - NSMinY(root.bounds)
				: NSMaxY(root.bounds) - NSMaxY(rect);
			NSMutableDictionary *probe = [@{@"id":identifier, @"x":@(NSMinX(rect) - NSMinX(root.bounds)),
				@"y":@(y), @"width":@(rect.size.width), @"height":@(rect.size.height)} mutableCopy];
			if ([view isKindOfClass:NSTextField.class]) probe[@"text"] = ((NSTextField *)view).stringValue;
			[probes addObject:probe];
			lua_pop(L, 2);
		}
		result[@"probes"] = probes;
		result[@"platform"] = @"macos";
		result[@"os"] = NSProcessInfo.processInfo.operatingSystemVersionString;
		result[@"scale"] = @(NSScreen.mainScreen.backingScaleFactor ?: 1);
		result[@"appearance"] = @"light";
		result[@"locale"] = NSLocale.currentLocale.localeIdentifier;
		result[@"textSize"] = @"large";
		result[@"direction"] = @"ltr";
		result[@"coordinateSpace"] = @"root-top-left-points";
		return parity_push_json(L, result);
	}
}
