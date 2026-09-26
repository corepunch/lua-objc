#pragma mark - TableView bridge (UITableView)

static NSMutableDictionary *lua_table_to_dict(lua_State *L, int idx) {
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	lua_pushnil(L);
	while (lua_next(L, idx) != 0) {
		if (lua_type(L, -2) == LUA_TSTRING) {
			const char *key = lua_tostring(L, -2);
			const char *val = lua_tostring(L, -1);
			if (key) {
				dict[[NSString stringWithUTF8String:key]] =
					[NSString stringWithUTF8String:val ?: ""];
			}
		}
		lua_pop(L, 1);
	}
	return dict;
}

static int bridge_tableview(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	UITableView *tv = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, width, height)
													style:UITableViewStylePlain];

	NSMutableArray *colSpecs = [NSMutableArray array];
	int ncols = (int)luaL_len(L, 1);
	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		NSDictionary *column = lua_to_objc_value(L, -1);
		lua_pop(L, 1);
		NSString *colId = column[@"id"];
		if (colId) {
			[colSpecs addObject:@{@"id": colId,
								  @"title": column[@"title"] ?: colId}];
		}
	}

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];

	objc_setAssociatedObject(tv, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(tv, &kTableSourceKey, src, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, tv, "uiview");
	return 1;
}

static int bridge_tableview_on_row_move(lua_State *L) {
	UITableView *table = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(table, &kTableSourceKey);
	if (!src) return luaL_error(L, "onRowMove requires a table view");
	src.moveReg = lua_reg_opt(L, 2);
	if (src.moveReg) {
		table.dragDelegate = src;
		table.dropDelegate = src;
		table.dragInteractionEnabled = YES;
	}
	return 0;
}

static int bridge_tableview_on_row_swipe(lua_State *L) {
	UITableView *table = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(table, &kTableSourceKey);
	if (!source) return luaL_error(L, "onRowSwipe requires a table view");
	const char *edge = luaL_checkstring(L, 2);
	NSString *title = [NSString stringWithUTF8String:luaL_checkstring(L, 3)];
	BOOL destructive = strcmp(luaL_optstring(L, 4, "normal"), "destructive") == 0;
	BOOL fullSwipe = lua_toboolean(L, 5);
	LuaReg *callback = lua_reg_opt(L, 6);
	if (strcmp(edge, "leading") == 0) {
		source.leadingSwipeReg = callback;
		source.leadingSwipeTitle = title;
		source.leadingSwipeDestructive = destructive;
		source.leadingFullSwipe = fullSwipe;
	} else if (strcmp(edge, "trailing") == 0) {
		source.trailingSwipeReg = callback;
		source.trailingSwipeTitle = title;
		source.trailingSwipeDestructive = destructive;
		source.trailingFullSwipe = fullSwipe;
	} else return luaL_error(L, "swipe edge must be leading or trailing");
	return 0;
}

static int bridge_test_row_swipe(lua_State *L) {
	UITableView *table = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(table, &kTableSourceKey);
	if (!source) return luaL_error(L, "row swipe test requires a table view");
	NSInteger row = (NSInteger)luaL_checkinteger(L, 2) - 1;
	const char *edge = luaL_checkstring(L, 3);
	if (strcmp(edge, "leading") != 0 && strcmp(edge, "trailing") != 0)
		return luaL_error(L, "swipe edge must be leading or trailing");
	lua_pushboolean(L, [source invokeSwipeAtRow:row leading:strcmp(edge, "leading") == 0]);
	return 1;
}

static int bridge_tableview_add(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	luaL_checktype(L, 2, LUA_TTABLE);
	[src addRow:lua_table_to_dict(L, 2)];
	if ([obj isKindOfClass:UITableView.class] && !((UITableView *)obj).scrollEnabled)
		uikit_invalidate_layout((UIView *)obj);
	return 0;
}

static int bridge_tableview_remove(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	[src removeRowAtIndex:(NSInteger)luaL_checkinteger(L, 2)];
	if ([obj isKindOfClass:UITableView.class] && !((UITableView *)obj).scrollEnabled)
		uikit_invalidate_layout((UIView *)obj);
	return 0;
}

static int bridge_tableview_clear(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	[src clearRows];
	if ([obj isKindOfClass:UITableView.class] && !((UITableView *)obj).scrollEnabled)
		uikit_invalidate_layout((UIView *)obj);
	return 0;
}
