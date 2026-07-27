#pragma mark - LuaOutlineViewSource

/* NSOutlineView data source that mirrors a Lua-side tree of name/path/children
 * tables. Each row is an NSMutableDictionary with optional @"children" array.
 * Supports single-column display with systemImage (folder vs file icons). */
@interface LuaOutlineViewSource : NSObject <NSOutlineViewDataSource,
	NSOutlineViewDelegate> {
	NSMutableArray *_rootRows;      /* top-level items */
	NSOutlineView *_outlineView;
	NSArray     *_columns;
}
@property (nonatomic, weak) LuaStateOwner *owner;
- (instancetype)initWithOutlineView:(NSOutlineView *)ov columns:(NSArray *)cols;
- (void)addRootItem:(NSDictionary *)item;
- (void)addChildItem:(NSDictionary *)item parent:(NSDictionary *)parent;
- (void)clearAll;
- (void)replaceRootItems:(NSArray *)items;
- (NSInteger)rowCount;
- (void)updateTableFrame;
- (void)activateSelectedRow:(id)sender;
@end

@implementation LuaOutlineViewSource

- (instancetype)initWithOutlineView:(NSOutlineView *)ov columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_outlineView = ov;
		_columns = [cols copy];
		_rootRows = [NSMutableArray array];
		ov.dataSource = self;
		ov.delegate = self;
	}
	return self;
}

- (void)dealloc {
	_outlineView.dataSource = nil;
	_outlineView.delegate = nil;
}

- (void)updateTableFrame {
	NSClipView *clipView = (NSClipView *)_outlineView.superview;
	if (![clipView isKindOfClass:[NSClipView class]]) return;

	CGFloat headerHeight = _outlineView.headerView
		? _outlineView.headerView.frame.size.height : 0;
	CGFloat rowsHeight = _outlineView.numberOfRows * _outlineView.rowHeight
		+ headerHeight;
	NSSize viewport = clipView.bounds.size;

	CGFloat totalColumnWidth = 0;
	for (NSTableColumn *col in _outlineView.tableColumns) {
		totalColumnWidth += col.width;
	}
	BOOL overflows = totalColumnWidth > viewport.width;

	CGRect frame = _outlineView.frame;
	frame.size.width = overflows ? totalColumnWidth : viewport.width;
	frame.size.height = MAX(viewport.height, rowsHeight);
	_outlineView.frame = frame;

	NSScrollView *sv = _outlineView.enclosingScrollView;
	sv.hasHorizontalScroller = overflows;
	if (!overflows) {
		[_outlineView sizeLastColumnToFit];
	}
}

- (void)addRootItem:(NSDictionary *)item {
	[_rootRows addObject:[item mutableCopy]];
	[_outlineView reloadData];
	[self updateTableFrame];
}

- (void)addChildItem:(NSDictionary *)item parent:(NSMutableDictionary *)parent {
	NSMutableArray *children = parent[@"children"];
	if (!children) {
		children = [NSMutableArray array];
		parent[@"children"] = children;
	}
	[children addObject:[item mutableCopy]];
	[_outlineView reloadData];
	[self updateTableFrame];
}

- (void)clearAll {
	[_rootRows removeAllObjects];
	[_outlineView reloadData];
}

- (void)replaceRootItems:(NSArray *)items {
	_rootRows = [items mutableCopy];
	[_outlineView reloadData];
	[self updateTableFrame];
}

- (NSInteger)rowCount {
	return _outlineView.numberOfRows;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
	if (!item) return (NSInteger)_rootRows.count;
	return [(NSArray *)((NSDictionary *)item)[@"children"] count];
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(id)item {
	if (!item) return _rootRows[idx];
	return ((NSDictionary *)item)[@"children"][idx];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
	return ((NSDictionary *)item)[@"children"] != nil;
}

/* Single-column cells: use NSTextField in an NSTableCellView, matching the
 * NSTableView pattern. */
- (NSView *)outlineView:(NSOutlineView *)ov
	viewForTableColumn:(NSTableColumn *)column
				  item:(id)item
{
	NSDictionary *rowData = (NSDictionary *)item;
	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";

	NSString *reuseId = [@"outline-cell-" stringByAppendingString:colId];
	NSTableCellView *cell = [ov makeViewWithIdentifier:reuseId owner:self];
	if (!cell) {
		cell = [[LuaTableCellView alloc]
			initWithFrame:NSMakeRect(0, 0, column.width, ov.rowHeight)];
		cell.identifier = reuseId;

		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		imageView.imageScaling = NSImageScaleProportionallyDown;
		imageView.contentTintColor = NSColor.secondaryLabelColor;
		[cell addSubview:imageView];
		cell.imageView = imageView;

		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.bezeled = NO;
		tf.drawsBackground = NO;
		tf.editable = NO;
		tf.selectable = NO;
		tf.lineBreakMode = NSLineBreakByTruncatingTail;
		[cell addSubview:tf];
		cell.textField = tf;
	}
	cell.textField.stringValue = text;

	NSString *symbolName =
		objc_getAssociatedObject(column, &kKeys[kColumnSystemImageKey]);
	if (symbolName.length > 0) {
		NSString *iconName = rowData[@"children"] != nil
			? @"folder" : symbolName;
		NSImage *image = [NSImage imageWithSystemSymbolName:iconName
			accessibilityDescription:text];
		NSImageSymbolConfiguration *config =
		[NSImageSymbolConfiguration configurationWithPointSize:kTableCellSymbolPointSize
													 weight:NSFontWeightRegular];
		cell.imageView.image = [image imageWithSymbolConfiguration:config];
	} else {
		cell.imageView.image = nil;
	}

	NSNumber *alignment = objc_getAssociatedObject(column,
		&kKeys[kColumnAlignmentKey]);
	cell.textField.alignment = alignment
		? (NSTextAlignment)alignment.integerValue : NSTextAlignmentLeft;
	[cell setNeedsLayout:YES];
	return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = _outlineView.selectedRow;
	if (row < 0) return;

	NSScrollView *sv = _outlineView.enclosingScrollView;
	lua_State *callL = self.owner.L;
	if (!sv || !callL) return;

	NSNumber *refNum = objc_getAssociatedObject(sv,
		&kKeys[kTableSelectionKey]);
	if (!refNum) return;

	id item = [_outlineView itemAtRow:row];
	if (!item) return;
	NSDictionary *rowData = (NSDictionary *)item;

	lua_rawgeti(callL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(callL, sv, "nsview");
	lua_pushinteger(callL, (lua_Integer)row);
	lua_newtable(callL);
	for (NSString *key in rowData) {
		if ([key isEqualToString:@"children"]) continue;
		id val = rowData[key];
		const char *str = val && ![val isEqual:[NSNull null]]
			? [[val description] UTF8String] : NULL;
		lua_pushstring(callL, str ?: "");
		lua_setfield(callL, -2, [key UTF8String]);
	}
	int status = lua_pcall(callL, 3, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(callL, "outline selection");
		lua_pop(callL, 1);
	}
}

- (void)activateSelectedRow:(id)sender {
	NSInteger row = _outlineView.selectedRow;
	lua_State *callL = self.owner.L;
	if (row < 0 || !callL) return;
	id item = [_outlineView itemAtRow:row];
	if (!item) return;
	NSScrollView *sv = _outlineView.enclosingScrollView;
	NSNumber *refNum = objc_getAssociatedObject(sv,
		&kKeys[kTableActivationKey]);
	if (!refNum) return;

	NSDictionary *rowData = (NSDictionary *)item;
	lua_rawgeti(callL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(callL, sv, "nsview");
	lua_pushinteger(callL, (lua_Integer)row);
	lua_newtable(callL);
	for (NSString *key in rowData) {
		if ([key isEqualToString:@"children"]) continue;
		id value = rowData[key];
		lua_pushstring(callL, value ? [[value description] UTF8String] : "");
		lua_setfield(callL, -2, key.UTF8String);
	}
	if (lua_pcall(callL, 3, 0, 0) != LUA_OK) {
		report_lua_error(callL, "outline activation");
		lua_pop(callL, 1);
	}
}

@end
