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
		lua_getfield(L, -1, "id");
		lua_getfield(L, -2, "title");
		const char *colId = lua_tostring(L, -2);
		const char *colTitle = lua_tostring(L, -1);
		if (colId) {
			[colSpecs addObject:@{@"id": [NSString stringWithUTF8String:colId],
								  @"title": [NSString stringWithUTF8String:colTitle ?: colId]}];
		}
		lua_pop(L, 3);
	}

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];

	objc_setAssociatedObject(tv, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(tv, &kTableSourceKey, src, OBJC_ASSOCIATION_RETAIN);

	push_objc(L, tv, "uiview");
	return 1;
}

static int bridge_tableview_add(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	luaL_checktype(L, 2, LUA_TTABLE);
	[src addRow:lua_table_to_dict(L, 2)];
	return 0;
}

static int bridge_tableview_remove(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	[src removeRowAtIndex:(NSInteger)luaL_checkinteger(L, 2)];
	return 0;
}

static int bridge_tableview_clear(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kTableSourceKey);
	if (!src) return luaL_error(L, "not a table view");
	[src clearRows];
	return 0;
}

