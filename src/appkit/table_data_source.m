typedef struct {
	void *ptr;
} ObjCRef;

static void push_objc(lua_State *L, id obj, const char *meta);

#pragma mark - LuaTableViewSource

@interface LuaTableViewSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableArray *columns;
@property (nonatomic, weak) NSTableView *tableView;
- (void)updateTableFrame;
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

- (void)updateTableFrame {
	NSClipView *clipView = (NSClipView *)_tableView.superview;
	if (![clipView isKindOfClass:[NSClipView class]]) return;

	CGFloat headerHeight = _tableView.headerView
		? _tableView.headerView.frame.size.height : 0;
	CGFloat rowsHeight = _rows.count * _tableView.rowHeight + headerHeight;
	NSSize viewport = clipView.bounds.size;

	CGFloat totalColumnWidth = 0;
	for (NSTableColumn *col in _tableView.tableColumns) {
		totalColumnWidth += col.width;
	}
	BOOL overflows = totalColumnWidth > viewport.width;

	CGRect frame = _tableView.frame;
	frame.size.width = overflows ? totalColumnWidth : viewport.width;
	frame.size.height = MAX(viewport.height, rowsHeight);
	_tableView.frame = frame;

	NSScrollView *sv = _tableView.enclosingScrollView;
	sv.hasHorizontalScroller = overflows;
	if (!overflows) {
		[_tableView sizeLastColumnToFit];
	}
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	NSInteger row = _tableView.selectedRow;
	if (row < 0) return;

	NSScrollView *sv = _tableView.enclosingScrollView;
	if (!sv || !gL) return;

	NSNumber *refNum = objc_getAssociatedObject(sv, &kKeys[kTableSelectionKey]);
	if (!refNum) return;

	NSDictionary *rowData = _rows[row];
	lua_rawgeti(gL, LUA_REGISTRYINDEX, refNum.intValue);
	push_objc(gL, sv, "nsview");
	lua_pushinteger(gL, (lua_Integer)row);
	lua_newtable(gL);
	for (NSString *key in rowData) {
		id value = rowData[key];
		const char *str = value && ![value isEqual:[NSNull null]]
			? [[value description] UTF8String] : NULL;
		lua_pushstring(gL, str ?: "");
		lua_setfield(gL, -2, [key UTF8String]);
	}
	int status = lua_pcall(gL, 3, 0, 0);
	if (status != LUA_OK) {
		report_lua_error(gL, "table selection");
		lua_pop(gL, 1);
	}
}

@end
