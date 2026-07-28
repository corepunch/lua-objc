
static NSScrollView *table_scrollview(id obj) {
	return objc_getAssociatedObject(obj, &kKeys[kTableScrollViewKey])
		?: (NSScrollView *)obj;
}

static int bridge_action_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	const char *subtitle = luaL_optstring(L, 2, "");
	const char *symbol = luaL_optstring(L, 3, "");
	const char *style = luaL_optstring(L, 4, "plain");
	const char *detail = luaL_optstring(L, 5, "");
	BOOL hasAction = !lua_isnoneornil(L, 6);
	int ref = LUA_NOREF;
	if (hasAction) {
		luaL_checktype(L, 6, LUA_TFUNCTION);
		lua_pushvalue(L, 6);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	LuaActionButton *button = [[LuaActionButton alloc]
		initWithTitle:[NSString stringWithUTF8String:title]
			subtitle:[NSString stringWithUTF8String:subtitle]
			  symbol:[NSString stringWithUTF8String:symbol]
			  detail:[NSString stringWithUTF8String:detail]
			   style:[NSString stringWithUTF8String:style]];
	if (hasAction) {
		objc_setAssociatedObject(button, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		button.target = [LuaButtonTarget shared];
		button.action = @selector(onAction:);
	}
	push_objc(L, button, "nsview");
	return 1;
}


#pragma mark - Timer & spinner

static id lua_to_objc_recursive(lua_State *L, int idx);

static NSMutableDictionary *lua_table_to_dict(lua_State *L, int idx) {
	return (NSMutableDictionary *)lua_to_objc_recursive(L, idx);
}

/* Convert a Lua table (string or integer keys) to an ObjC collection.
 * String-keyed subtables become NSMutableDictionary, array-indexed ones
 * become NSMutableArray.  Leaf values become NSString.  This preserves
 * the tree structure needed by LuaOutlineViewSource. */
static id lua_to_objc_recursive(lua_State *L, int idx) {
	lua_pushvalue(L, idx);
	lua_pushnil(L);
	int firstKeyType = lua_next(L, -2) != 0 ? lua_type(L, -2) : LUA_TNIL;
	if (firstKeyType != LUA_TNIL) lua_pop(L, 2);  /* pop key+value */
	lua_pop(L, 1);  /* pop pushed copy */

	if (firstKeyType == LUA_TNIL) {
		/* Empty table — return empty dict */
		return [NSMutableDictionary dictionary];
	}

	if (firstKeyType == LUA_TNUMBER || firstKeyType == LUA_TSTRING) {
		BOOL isArray = (firstKeyType == LUA_TNUMBER);
		id result = isArray ? (id)[NSMutableArray array]
			: (id)[NSMutableDictionary dictionary];

		lua_pushvalue(L, idx);
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			id value = nil;
			if (lua_type(L, -1) == LUA_TTABLE) {
				value = lua_to_objc_recursive(L, lua_gettop(L));
			} else {
				const char *str = lua_tostring(L, -1);
				value = str ? [NSString stringWithUTF8String:str] : @"";
			}

			if (isArray) {
				[(NSMutableArray *)result addObject:value];
			} else {
				const char *key = lua_tostring(L, -2);
				if (key) {
					[(NSMutableDictionary *)result
						setObject:value
						forKey:[NSString stringWithUTF8String:key]];
				}
			}
			lua_pop(L, 1);
		}
		lua_pop(L, 1);

		return result;
	}

	/* Not a table — shouldn't happen */
	return [NSMutableDictionary dictionary];
}

static int bridge_tableview(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	__block BOOL showsHeader = YES;
	__block BOOL bordered = NO;
	__block BOOL alternatingRows = YES;
	__block BOOL drawsBackground = YES;
	__block int gridLines = 0;
	__block NSString *tableStyle = nil;

	if (lua_istable(L, 4)) {
		TablePropParser propParsers[] = {
			{"header",          ^(lua_State *L, int idx) { showsHeader = lua_toboolean(L, idx); }},
			{"bordered",        ^(lua_State *L, int idx) { bordered = lua_toboolean(L, idx); }},
			{"alternatingRows", ^(lua_State *L, int idx) { alternatingRows = lua_toboolean(L, idx); }},
			{"drawsBackground", ^(lua_State *L, int idx) { drawsBackground = lua_toboolean(L, idx); }},
			{"gridLines",       ^(lua_State *L, int idx) {
				const char *g = lua_tostring(L, idx);
				gridLines = g ? (int)lookupNameValue([NSString stringWithUTF8String:g], GridLinesMap, 0) : 0;
			}},
			{"style",           ^(lua_State *L, int idx) {
				const char *s = lua_tostring(L, idx);
				tableStyle = s ? [NSString stringWithUTF8String:s] : nil;
			}},
			{NULL, nil}
		};
		for (TablePropParser *p = propParsers; p->key; p++) {
			lua_getfield(L, 4, p->key);
			if (!lua_isnil(L, -1)) p->apply(L, -1);
			lua_pop(L, 1);
		}
	}

	int ncols = (int)luaL_len(L, 1);

	NSTableView *tv = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	NSInteger styleVal = lookupNameValue(tableStyle, TableStyleMap, -1);
	BOOL isSourceList = (styleVal == NSTableViewStyleSourceList);
	if (styleVal >= 0) tv.style = (NSTableViewStyle)styleVal;
	tv.headerView = showsHeader ? [[NSTableHeaderView alloc] init] : nil;
	tv.usesAlternatingRowBackgroundColors = isSourceList ? NO : alternatingRows;
	tv.gridStyleMask = (NSTableViewGridLineStyle)gridLines;
	tv.intercellSpacing = NSMakeSize(kTableIntercellSpacingH, kTableIntercellSpacingV);
	if (!drawsBackground) tv.backgroundColor = NSColor.clearColor;
	tv.allowsColumnReordering = NO;
	tv.allowsColumnResizing = YES;
	CGFloat colW = ncols > 0 ? width / ncols : width;
	NSMutableArray *colSpecs = [NSMutableArray array];

	BOOL hasFlexColumns = NO;

	for (int i = 1; i <= ncols; i++) {
		lua_rawgeti(L, 1, i);
		NSDictionary *column = lua_to_objc_value(L, -1);
		lua_pop(L, 1);

		NSString *colId = column[@"id"];
		if (!colId) continue;

		NSString *colTitle = column[@"title"] ?: colId;
		NSString *colAlignment = column[@"alignment"];
		NSString *systemImage = column[@"systemImage"];
		NSNumber *width = column[@"width"];
		NSNumber *minWidth = column[@"minWidth"];

		BOOL hasExplicitWidth = [width isKindOfClass:NSNumber.class];
		CGFloat requestedWidth = hasExplicitWidth
			? width.doubleValue : colW;
		CGFloat requestedMinWidth = [minWidth isKindOfClass:NSNumber.class]
			? minWidth.doubleValue : kTableColumnMinWidth;

		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:colId];
		col.title = colTitle;
		col.width = requestedWidth;
		col.minWidth = MAX(kTableColumnMinWidth, requestedMinWidth);
		NSTextAlignment alignment = colAlignment
			? (NSTextAlignment)lookupNameValue(colAlignment,
				AlignmentMap, NSTextAlignmentLeft)
			: NSTextAlignmentLeft;
		col.headerCell.alignment = alignment;
		objc_setAssociatedObject(col, &kKeys[kColumnAlignmentKey], @(alignment),
			OBJC_ASSOCIATION_RETAIN);
		if (systemImage) {
			objc_setAssociatedObject(col, &kKeys[kColumnSystemImageKey],
				systemImage, OBJC_ASSOCIATION_RETAIN);
		}
		if (!hasExplicitWidth) {
			objc_setAssociatedObject(col, &kKeys[kColumnFlexKey],
				@1.0, OBJC_ASSOCIATION_RETAIN);
			hasFlexColumns = YES;
		}
		[tv addTableColumn:col];

		[colSpecs addObject:@{@"id": colId, @"title": col.title}];
	}
	tv.columnAutoresizingStyle = hasFlexColumns
		? NSTableViewNoColumnAutoresizing
		: NSTableViewUniformColumnAutoresizingStyle;

	LuaTableViewSource *src = [[LuaTableViewSource alloc] initWithTableView:tv
																   columns:colSpecs];
	src.owner = owner_for_state(L);

	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	sv.documentView = tv;
	sv.hasVerticalScroller = YES;
	sv.autohidesScrollers = YES;
	sv.borderType = bordered ? NSBezelBorder : NSNoBorder;
	sv.drawsBackground = drawsBackground;
	if (isSourceList) {
		tv.backgroundColor = NSColor.clearColor;
		sv.drawsBackground = NO;
		sv.contentView.drawsBackground = NO;
	}

	objc_setAssociatedObject(sv, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(sv, &kKeys[kTableSourceKey], src, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, sv, "nsview");
	return 1;
}

static int bridge_toolbar_item(lua_State *L) {
	id obj = check_objc(L, 1);
	const char *identifier = luaL_checkstring(L, 2);
	if (![obj isKindOfClass:[NSWindow class]]) {
		return luaL_error(L, "ToolbarItem requires a window");
	}

	NSString *wanted = [NSString stringWithUTF8String:identifier];
	for (NSToolbarItem *item in ((NSWindow *)obj).toolbar.items) {
		if ([item.itemIdentifier isEqualToString:wanted]) {
			push_objc(L, item, "nsobject");
			return 1;
		}
	}

	lua_pushnil(L);
	return 1;
}

/* Return the canvas toolbar items stored on a canvas content view as a Lua
 * array of item tables (each with icon/label/tooltip string keys), or nil.
 * The items were extracted from the user code's Window.toolbar in the canvas
 * state and stored as an NSArray of NSDictionary via canvas_eval.m. */
static int bridge_canvas_toolbar_items(lua_State *L) {
	NSView *view = check_view(L, 1);
	NSArray<NSDictionary *> *items = objc_getAssociatedObject(view, &kKeys[kCanvasToolbarItemsKey]);
	if (!items || items.count == 0) {
		lua_pushnil(L);
		return 1;
	}

	lua_newtable(L);
	int i = 1;
	for (NSDictionary *dict in items) {
		lua_newtable(L);
		NSString *icon = dict[@"icon"];
		NSString *label = dict[@"label"];
		NSString *tooltip = dict[@"tooltip"];
		if (icon)    { lua_pushstring(L, icon.UTF8String);    lua_setfield(L, -2, "icon"); }
		if (label)   { lua_pushstring(L, label.UTF8String);   lua_setfield(L, -2, "label"); }
		if (tooltip) { lua_pushstring(L, tooltip.UTF8String); lua_setfield(L, -2, "tooltip"); }
		lua_rawseti(L, -2, i++);
	}
	return 1;
}

static int bridge_tableview_add(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");

	luaL_checktype(L, 2, LUA_TTABLE);
	NSMutableDictionary *row = lua_table_to_dict(L, 2);
	if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
		[(LuaOutlineViewSource *)src addRootItem:row];
	} else {
		[(LuaTableViewSource *)src addRow:row];
	}
	return 0;
}

static int bridge_tableview_remove(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	int idx = (int)luaL_checkinteger(L, 2);
	[src removeRowAtIndex:(NSInteger)idx];
	return 0;
}

static int bridge_tableview_clear(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");

	if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
		[(LuaOutlineViewSource *)src clearAll];
	} else {
		[(LuaTableViewSource *)src clearRows];
	}
	return 0;
}

static int bridge_tableview_replace(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");
	luaL_checktype(L, 2, LUA_TTABLE);

	NSMutableArray *rows = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 2);
	for (lua_Integer index = 1; index <= count; index++) {
		lua_rawgeti(L, 2, index);
		if (lua_istable(L, -1)) {
			[rows addObject:lua_table_to_dict(L, lua_gettop(L))];
		}
		lua_pop(L, 1);
	}

	if ([src isKindOfClass:[LuaOutlineViewSource class]]) {
		[(LuaOutlineViewSource *)src replaceRootItems:rows];
	} else {
		[(LuaTableViewSource *)src replaceRows:rows];
	}
	return 0;
}

static int bridge_table_show_loading(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSScrollView *sv = (NSScrollView *)obj;
	NSProgressIndicator *spinner = objc_getAssociatedObject(sv, &kKeys[kTableSpinnerKey]);
	if (spinner) {
		[spinner startAnimation:nil];
		return 0;
	}

	spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, kLoadingSpinnerSize, kLoadingSpinnerSize)];
	spinner.style = NSProgressIndicatorStyleSpinning;
	spinner.controlSize = NSControlSizeRegular;
	spinner.displayedWhenStopped = NO;
	[spinner sizeToFit];

	CGFloat sw = spinner.frame.size.width;
	CGFloat sh = spinner.frame.size.height;
	spinner.frame = NSMakeRect(
		(sv.bounds.size.width - sw) / 2,
		(sv.bounds.size.height - sh) / 2,
		sw, sh);
	spinner.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin
		| NSViewMinYMargin | NSViewMaxYMargin;

	objc_setAssociatedObject(sv, &kKeys[kTableSpinnerKey], spinner,
		OBJC_ASSOCIATION_RETAIN);
	[sv addSubview:spinner];
	[spinner startAnimation:nil];
	return 0;
}

static int bridge_table_hide_loading(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSScrollView *sv = (NSScrollView *)obj;
	NSProgressIndicator *spinner = objc_getAssociatedObject(sv, &kKeys[kTableSpinnerKey]);
	if (spinner) {
		[spinner stopAnimation:nil];
		[spinner removeFromSuperview];
		objc_setAssociatedObject(sv, &kKeys[kTableSpinnerKey], nil,
			OBJC_ASSOCIATION_RETAIN);
	}
	return 0;
}

static int bridge_table_column_widths(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSScrollView *sv = (NSScrollView *)obj;
	NSTableView *tv = (NSTableView *)sv.documentView;
	if (![tv isKindOfClass:[NSTableView class]]) return 0;

	lua_newtable(L);
	NSArray<NSTableColumn *> *columns = tv.tableColumns;
	for (NSUInteger i = 0; i < columns.count; i++) {
		NSTableColumn *col = columns[i];
		lua_newtable(L);
		lua_pushstring(L, col.identifier.UTF8String);
		lua_setfield(L, -2, "id");
		lua_pushnumber(L, col.width);
		lua_setfield(L, -2, "width");
		lua_pushnumber(L, col.minWidth);
		lua_setfield(L, -2, "minWidth");
		lua_rawseti(L, -2, (lua_Integer)(i + 1));
	}
	return 1;
}

static int bridge_table_cell_frames(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSScrollView *sv = (NSScrollView *)obj;
	NSTableView *tv = (NSTableView *)sv.documentView;
	if (![tv isKindOfClass:[NSTableView class]]) return 0;

	NSInteger row = (NSInteger)luaL_optinteger(L, 2, 0);
	if (row < 0 || row >= tv.numberOfRows) {
		return luaL_error(L, "table row out of bounds");
	}

	lua_newtable(L);
	NSArray<NSTableColumn *> *columns = tv.tableColumns;
	for (NSUInteger i = 0; i < columns.count; i++) {
		NSTableColumn *col = columns[i];
		NSRect frame = [tv frameOfCellAtColumn:(NSInteger)i row:row];
		lua_newtable(L);
		lua_pushstring(L, col.identifier.UTF8String);
		lua_setfield(L, -2, "id");
		lua_pushnumber(L, frame.origin.x);
		lua_setfield(L, -2, "x");
		lua_pushnumber(L, frame.size.width);
		lua_setfield(L, -2, "width");
		lua_pushnumber(L, NSMaxX(frame));
		lua_setfield(L, -2, "maxX");
		lua_rawseti(L, -2, (lua_Integer)(i + 1));
	}
	return 1;
}


static int bridge_table_refresh(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");

	NSNumber *refNum = objc_getAssociatedObject(obj, &kKeys[kTableRefreshKey]);
	if (!refNum) { lua_pushboolean(L, 0); return 1; }

	lua_rawgeti(L, LUA_REGISTRYINDEX, refNum.intValue);
	lua_pushvalue(L, 1);
	if (!lua_isnoneornil(L, 2)) {
		lua_pushvalue(L, 2);
	} else {
		lua_pushnil(L);
	}
	lua_objc_pcall(L, 2, 0, "refresh");
	lua_pushboolean(L, 1);
	return 1;
}

static int bridge_table_select_row(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");
	NSTableView *table = (NSTableView *)((NSScrollView *)obj).documentView;

	if (lua_isnoneornil(L, 2)) {
		[table deselectAll:nil];
		return 0;
	}
	NSInteger row = (NSInteger)luaL_checkinteger(L, 2);
	if (row < 0 || row >= table.numberOfRows) return 0;
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
		byExtendingSelection:NO];
	[table scrollRowToVisible:row];
	return 0;
}

static int bridge_table_activate_row(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");
	NSScrollView *sv = (NSScrollView *)obj;
	NSTableView *table = (NSTableView *)sv.documentView;
	NSInteger row = (NSInteger)luaL_checkinteger(L, 2);
	if (row < 0 || row >= table.numberOfRows) return 0;
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
		byExtendingSelection:NO];
	[table scrollRowToVisible:row];
	if ([src respondsToSelector:@selector(activateSelectedRow:)]) {
		[src activateSelectedRow:table];
	}
	return 0;
}
