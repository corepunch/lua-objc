#pragma mark - Outline View

static int bridge_outlineview(lua_State *L) {
	__block BOOL bordered = NO;
	__block BOOL header = YES;
	__block BOOL alternatingRows = YES;
	__block BOOL drawsBackground = YES;
	__block int gridLines = 0;
	__block NSString *tableStyle = nil;

	luaL_checktype(L, 1, LUA_TTABLE);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	if (lua_gettop(L) >= 4 && lua_istable(L, 4)) {
		TablePropParser propParsers[] = {
			{"header",          ^(lua_State *L, int idx) { header = lua_toboolean(L, idx); }},
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

	NSOutlineView *ov = [[NSOutlineView alloc]
		initWithFrame:NSMakeRect(0, 0, width, height)];
	NSInteger styleVal = lookupNameValue(tableStyle, TableStyleMap, -1);
	BOOL isSourceList = (styleVal == NSTableViewStyleSourceList);
	if (styleVal >= 0) ov.style = (NSTableViewStyle)styleVal;
	ov.headerView = header ? [[NSTableHeaderView alloc] init] : nil;
	ov.usesAlternatingRowBackgroundColors = isSourceList ? NO : alternatingRows;
	ov.gridStyleMask = (NSTableViewGridLineStyle)gridLines;
	ov.rowHeight = kOutlineRowHeight;
	ov.intercellSpacing = NSMakeSize(3, 2);
	if (!drawsBackground) ov.backgroundColor = NSColor.clearColor;
	ov.allowsColumnReordering = NO;
	ov.allowsColumnResizing = YES;
	ov.indentationPerLevel = kOutlineIndentation;
	ov.indentationMarkerFollowsCell = YES;
	ov.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;

	int ncols = (int)luaL_len(L, 1);
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
		objc_setAssociatedObject(col, &kKeys[kColumnAlignmentKey],
			@(alignment), OBJC_ASSOCIATION_RETAIN);
		if (systemImage) {
			objc_setAssociatedObject(col, &kKeys[kColumnSystemImageKey],
				systemImage, OBJC_ASSOCIATION_RETAIN);
		}
		if (!hasExplicitWidth) {
			objc_setAssociatedObject(col, &kKeys[kColumnFlexKey],
				@1.0, OBJC_ASSOCIATION_RETAIN);
			hasFlexColumns = YES;
		}
		[ov addTableColumn:col];
		[colSpecs addObject:@{@"id": colId, @"title": col.title}];
	}
	ov.columnAutoresizingStyle = hasFlexColumns
		? NSTableViewNoColumnAutoresizing
		: NSTableViewUniformColumnAutoresizingStyle;

	LuaOutlineViewSource *src = [[LuaOutlineViewSource alloc]
		initWithOutlineView:ov columns:colSpecs];
	src.owner = owner_for_state(L);

	NSScrollView *sv = [[NSScrollView alloc]
		initWithFrame:NSMakeRect(0, 0, width, height)];
	sv.documentView = ov;
	sv.hasVerticalScroller = YES;
	sv.autohidesScrollers = YES;
	sv.borderType = bordered ? NSBezelBorder : NSNoBorder;
	sv.drawsBackground = drawsBackground;
	if (isSourceList) sv.drawsBackground = NO;

	if (isSourceList) {
		NSVisualEffectView *vev = [[NSVisualEffectView alloc]
			initWithFrame:NSMakeRect(0, 0, width, height)];
		vev.material = NSVisualEffectMaterialSidebar;
		vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
		vev.state = NSVisualEffectStateFollowsWindowActiveState;
		sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[vev addSubview:sv];
		objc_setAssociatedObject(vev, &kKeys[kFlexibleKey], @YES,
			OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(vev, &kKeys[kTableSourceKey], src,
			OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(vev, &kKeys[kTableScrollViewKey], sv,
			OBJC_ASSOCIATION_RETAIN);
		push_objc(L, vev, "nsview");
	} else {
		objc_setAssociatedObject(sv, &kKeys[kFlexibleKey], @YES,
			OBJC_ASSOCIATION_RETAIN);
		objc_setAssociatedObject(sv, &kKeys[kTableSourceKey], src,
			OBJC_ASSOCIATION_RETAIN);
		push_objc(L, sv, "nsview");
	}
	return 1;
}

#pragma mark - Directory listing

/* Internal helper: list directory contents into a Lua table on the stack.
 * path and depth are C strings/ints, not read from the Lua stack.
 * Always pushes exactly one value (the result table, or nil on error). */
static void list_dir_into_table(lua_State *L, const char *raw, int depth) {
	NSString *dirPath = [NSString stringWithUTF8String:raw];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *contents = [fm contentsOfDirectoryAtPath:dirPath error:nil];
	if (!contents) { lua_pushnil(L); return; }

	/* Sort: directories first, then alpha by name */
	contents = [contents sortedArrayUsingComparator:^NSComparisonResult(
		id a, id b) {
		NSString *pa = [dirPath stringByAppendingPathComponent:a];
		NSString *pb = [dirPath stringByAppendingPathComponent:b];
		BOOL ad = NO, bd = NO;
		[fm fileExistsAtPath:pa isDirectory:&ad];
		[fm fileExistsAtPath:pb isDirectory:&bd];
		if (ad != bd) return ad ? NSOrderedAscending : NSOrderedDescending;
		return [(NSString *)a caseInsensitiveCompare:(NSString *)b];
	}];

	lua_newtable(L);
	int ti = 1;

	for (NSString *name in contents) {
		NSString *full = [dirPath stringByAppendingPathComponent:name];
		BOOL isDir = NO;
		[fm fileExistsAtPath:full isDirectory:&isDir];

		/* Skip hidden files/directories */
		if ([name hasPrefix:@"."]) continue;

		lua_newtable(L);
		lua_pushstring(L, name.UTF8String);
		lua_setfield(L, -2, "name");
		lua_pushstring(L, full.UTF8String);
		lua_setfield(L, -2, "path");
		if (isDir) {
			lua_pushboolean(L, 1);
			lua_setfield(L, -2, "directory");
			if (depth > 0) {
				list_dir_into_table(L, full.UTF8String, depth - 1);
				lua_setfield(L, -2, "children");
			}
		}
		lua_rawseti(L, -2, ti++);
	}
}

static int bridge_list_directory(lua_State *L) {
	const char *raw = luaL_checkstring(L, 1);
	int depth = lua_isnumber(L, 2) ? (int)lua_tointeger(L, 2) : 0;
	list_dir_into_table(L, raw, depth);
	return 1;
}
