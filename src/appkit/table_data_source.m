typedef struct {
	void *ptr;
} ObjCRef;

static void push_objc(lua_State *L, id obj, const char *meta);

#pragma mark - LuaTableViewSource

@interface LuaTableViewSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) NSTableView *tableView;
@property (nonatomic, weak) LuaStateOwner *owner;
- (void)updateTableFrame;
- (void)replaceRows:(NSArray *)rows;
- (void)activateSelectedRow:(id)sender;
@end

@interface LuaTableCellView : NSTableCellView
@end

@implementation LuaTableCellView

- (void)layout {
	[super layout];
	NSTextField *text = self.textField;
	if (!text) return;
	NSImageView *image = self.imageView;
	CGFloat imageWidth = image.image ? kTableCellImageWidth : 0;
	CGFloat imageGap = imageWidth > 0 ? kTableCellImageTextGap : 0;
	CGFloat textInset = imageWidth > 0 ? kTableCellImageLeadingInset : kTableCellTextLeadingInset;
	CGFloat textX = textInset + imageWidth + imageGap;
	CGFloat height = ceil(text.intrinsicContentSize.height);
	text.frame = NSMakeRect(
		textX,
		floor((self.bounds.size.height - height) / 2),
		MAX(0, self.bounds.size.width - textX - kTableCellTextTrailingInset),
		height);
	if (image) {
		image.frame = NSMakeRect(
			textInset,
			floor((self.bounds.size.height - imageWidth) / 2),
			imageWidth,
			imageWidth);
	}
}

@end

@implementation LuaTableViewSource

- (instancetype)initWithTableView:(NSTableView *)tv columns:(NSArray *)cols {
	self = [super init];
	if (self) {
		_tableView = tv;
		_columns = [cols mutableCopy];
		_rows = [NSMutableArray array];
		tv.dataSource = self;
		tv.delegate = self;
	}
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return (NSInteger)_rows.count;
}

- (CGFloat)horizontalCellOverhead {
	/*
	 * Source-list styling applies a native leading inset to row cells, and
	 * NSTableView places inter-column spacing outside the declared widths.
	 * Measure both from AppKit's actual last-cell frame so fixed and flexible
	 * columns remain inside the clip view without duplicating system metrics.
	 */
	if (_tableView.style != NSTableViewStyleSourceList ||
		_rows.count == 0 || _tableView.tableColumns.count == 0) return 0;

	CGFloat declaredWidth = 0;
	for (NSTableColumn *col in _tableView.tableColumns) {
		declaredWidth += col.width;
	}
	NSRect lastCell = [_tableView frameOfCellAtColumn:
		(NSInteger)_tableView.tableColumns.count - 1 row:0];
	return MAX(0, NSMaxX(lastCell) - declaredWidth);
}

- (void)updateTableFrame {
	NSClipView *clipView = (NSClipView *)_tableView.superview;
	if (![clipView isKindOfClass:[NSClipView class]]) return;

	CGFloat headerHeight = _tableView.headerView
		? _tableView.headerView.frame.size.height : 0;
	CGFloat rowsHeight = _rows.count * _tableView.rowHeight + headerHeight;
	NSSize viewport = clipView.bounds.size;

	/*
	 * Separate columns into fixed and flex groups. When no flex columns
	 * are present, the old sizeLastColumnToFit behaviour is preserved.
	 * When flex columns exist, they split remaining space by their flex
	 * weight; if the viewport is too narrow even for minimum widths, a
	 * horizontal scroller appears.
	 */
	CGFloat fixedDesired = 0, flexTotalWeight = 0, allMin = 0;
	BOOL hasFlex = NO;

	for (NSTableColumn *col in _tableView.tableColumns) {
		NSNumber *flexN = objc_getAssociatedObject(col, &kKeys[kColumnFlexKey]);
		CGFloat flex = flexN ? flexN.doubleValue : 0;
		allMin += col.minWidth;
		if (flex > 0) {
			flexTotalWeight += flex;
			hasFlex = YES;
		} else {
			fixedDesired += col.width;
		}
	}

	BOOL overflows = NO;
	CGFloat tableWidth = viewport.width;
	CGFloat cellOverhead = [self horizontalCellOverhead];

	if (hasFlex) {
		CGFloat remaining = viewport.width - fixedDesired - cellOverhead;
		if (remaining > 0) {
			for (NSTableColumn *col in _tableView.tableColumns) {
				NSNumber *flexN = objc_getAssociatedObject(
					col, &kKeys[kColumnFlexKey]);
				CGFloat flex = flexN ? flexN.doubleValue : 0;
				if (flex > 0) {
					col.width = remaining * flex / flexTotalWeight;
				}
			}
		} else {
			for (NSTableColumn *col in _tableView.tableColumns) {
				col.width = col.minWidth;
			}
			overflows = (viewport.width < allMin + cellOverhead);
			if (overflows) tableWidth = allMin + cellOverhead;
		}
	} else {
		CGFloat totalColumnWidth = 0;
		for (NSTableColumn *col in _tableView.tableColumns) {
			totalColumnWidth += col.width;
		}
		CGFloat contentWidth = totalColumnWidth + cellOverhead;
		overflows = contentWidth > viewport.width;
		if (overflows) tableWidth = contentWidth;
		if (!overflows) {
			[_tableView sizeLastColumnToFit];
		}
	}

	CGRect frame = _tableView.frame;
	frame.size.width = tableWidth;
	frame.size.height = MAX(viewport.height, rowsHeight);
	_tableView.frame = frame;

	NSScrollView *sv = _tableView.enclosingScrollView;
	sv.hasHorizontalScroller = overflows;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)column
				  row:(NSInteger)row
{
	NSDictionary *rowData = _rows[row];
	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";

	NSString *reuseId = [@"cell-" stringByAppendingString:column.identifier];
	NSTableCellView *cell = [tableView makeViewWithIdentifier:reuseId owner:self];
	if (!cell) {
		cell = [[LuaTableCellView alloc] initWithFrame:
			NSMakeRect(0, 0, column.width, tableView.rowHeight)];
		cell.identifier = reuseId;

		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.bezeled = NO;
		tf.drawsBackground = NO;
		tf.editable = NO;
		tf.selectable = NO;
		tf.lineBreakMode = NSLineBreakByTruncatingTail;

		[cell addSubview:tf];
		cell.textField = tf;

		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		imageView.imageScaling = NSImageScaleProportionallyDown;
		imageView.contentTintColor = NSColor.secondaryLabelColor;
		[cell addSubview:imageView];
		cell.imageView = imageView;
	}
	cell.textField.stringValue = text;
	NSString *symbolName = objc_getAssociatedObject(
		column, &kKeys[kColumnSystemImageKey]);
	if (symbolName.length > 0) {
		NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
			accessibilityDescription:text];
		NSImageSymbolConfiguration *configuration =
		[NSImageSymbolConfiguration configurationWithPointSize:kTableCellSymbolPointSize
													 weight:NSFontWeightRegular];
		cell.imageView.image = [image imageWithSymbolConfiguration:configuration];
	} else {
		cell.imageView.image = nil;
	}
	NSNumber *alignment = objc_getAssociatedObject(column, &kKeys[kColumnAlignmentKey]);
	cell.textField.alignment = alignment
		? (NSTextAlignment)alignment.integerValue : NSTextAlignmentLeft;
	[cell setNeedsLayout:YES];
	return cell;
}

- (void)addRow:(NSDictionary *)row {
	[_rows addObject:row];
	NSInteger idx = (NSInteger)_rows.count - 1;
	[_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:idx]
					  withAnimation:NSTableViewAnimationSlideDown];
	[self updateTableFrame];
}

- (void)removeRowAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_rows.count) return;
	[_rows removeObjectAtIndex:(NSUInteger)index];
	[_tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:index]
					  withAnimation:NSTableViewAnimationSlideUp];
	[self updateTableFrame];
}

- (void)clearRows {
	[_rows removeAllObjects];
	[_tableView reloadData];
	[self updateTableFrame];
}

- (void)replaceRows:(NSArray *)rows {
	_rows = [rows mutableCopy];
	[_tableView reloadData];
	[self updateTableFrame];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = _tableView.selectedRow;
	if (row < 0) return;

	NSScrollView *sv = _tableView.enclosingScrollView;
	lua_State *callL = _owner.L;
	if (!sv || !callL) return;

	NSNumber *refNum = objc_getAssociatedObject(sv, &kKeys[kTableSelectionKey]);
	if (!refNum) return;

	NSDictionary *rowData = _rows[row];
	lua_rawgeti(callL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(callL, sv, "nsview");
	lua_pushinteger(callL, (lua_Integer)row);
	lua_newtable(callL);
	for (NSString *key in rowData) {
		id value = rowData[key];
		const char *str = value && ![value isEqual:[NSNull null]]
			? [[value description] UTF8String] : NULL;
		lua_pushstring(callL, str ?: "");
		lua_setfield(callL, -2, [key UTF8String]);
	}
	int status = lua_pcall(callL, 3, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(callL, "table selection");
		lua_pop(callL, 1);
	}
}

- (void)activateSelectedRow:(id)sender {
	NSInteger row = _tableView.selectedRow;
	lua_State *callL = _owner.L;
	if (row < 0 || row >= (NSInteger)_rows.count || !callL) return;
	NSScrollView *sv = _tableView.enclosingScrollView;
	NSNumber *refNum = objc_getAssociatedObject(sv,
		&kKeys[kTableActivationKey]);
	if (!refNum) return;

	NSDictionary *rowData = _rows[row];
	lua_rawgeti(callL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(callL, sv, "nsview");
	lua_pushinteger(callL, (lua_Integer)row);
	lua_newtable(callL);
	for (NSString *key in rowData) {
		id value = rowData[key];
		lua_pushstring(callL, value ? [[value description] UTF8String] : "");
		lua_setfield(callL, -2, key.UTF8String);
	}
	if (lua_pcall(callL, 3, 0, 0) != LUA_OK) {
		report_lua_error(callL, "table activation");
		lua_pop(callL, 1);
	}
}

@end
