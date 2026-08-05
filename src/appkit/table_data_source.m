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
@property (nonatomic, strong) NSTextField *secondaryTextField;
@property (nonatomic, strong) LuaPathView *curveView;
@end

@implementation LuaTableCellView

- (void)layout {
	[super layout];
	NSTextField *text = self.textField;
	if (!text) return;
	if (_curveView && !_curveView.hidden) {
		_curveView.frame = NSInsetRect(
			self.bounds, kTableCellCurveInsetH, kTableCellCurveInsetV);
		return;
	}
	NSImageView *image = self.imageView;
	CGFloat imageWidth = image.image ? kTableCellImageWidth : 0;
	CGFloat imageGap = imageWidth > 0 ? kTableCellImageTextGap : 0;
	CGFloat textInset = imageWidth > 0 ? kTableCellImageLeadingInset : kTableCellTextLeadingInset;
	CGFloat textX = textInset + imageWidth + imageGap;
	BOOL hasSecondary = _secondaryTextField.stringValue.length > 0;
	CGFloat height = ceil(text.intrinsicContentSize.height);
	CGFloat secondaryHeight = hasSecondary
		? ceil(_secondaryTextField.intrinsicContentSize.height) : 0;
	CGFloat totalHeight = height + secondaryHeight
		+ (hasSecondary ? kTableCellLineSpacing : 0);
	CGFloat textY = floor((self.bounds.size.height - totalHeight) / 2)
		+ secondaryHeight + (hasSecondary ? kTableCellLineSpacing : 0);
	text.frame = NSMakeRect(
		textX,
		textY,
		MAX(0, self.bounds.size.width - textX - kTableCellTextTrailingInset),
		height);
	if (hasSecondary) {
		_secondaryTextField.frame = NSMakeRect(
			textX,
			floor((self.bounds.size.height - totalHeight) / 2),
			MAX(0, self.bounds.size.width - textX
				- kTableCellTextTrailingInset),
			secondaryHeight);
	}
	if (image) {
		image.frame = NSMakeRect(
			textInset,
			floor((self.bounds.size.height - imageWidth) / 2),
			imageWidth,
			imageWidth);
	}
}

@end

static NSColor *table_semantic_color(NSString *name) {
	if ([name isEqualToString:@"systemGreen"]) return NSColor.systemGreenColor;
	if ([name isEqualToString:@"systemRed"]) return NSColor.systemRedColor;
	if ([name isEqualToString:@"secondary"]) return NSColor.secondaryLabelColor;
	return NSColor.labelColor;
}

static void table_update_curve(
	LuaPathView *curve, NSArray *values, NSColor *color) {
	if (!curve) return;
	[curve.path removeAllPoints];
	curve.hidden = values.count < 2;
	if (curve.hidden) return;
	double minimum = [values.firstObject doubleValue];
	double maximum = minimum;
	for (id value in values) {
		double number = [value doubleValue];
		minimum = MIN(minimum, number);
		maximum = MAX(maximum, number);
	}
	double range = maximum - minimum;
	if (range == 0) range = 1;
	for (NSUInteger index = 0; index < values.count; index++) {
		CGFloat x = kTableCellCurvePathWidth * index / MAX(1, values.count - 1);
		CGFloat y = kTableCellCurvePathHeight
			* (1 - ([values[index] doubleValue] - minimum) / range);
		if (index == 0) [curve.path moveToPoint:NSMakePoint(x, y)];
		else [curve.path lineToPoint:NSMakePoint(x, y)];
	}
	curve.pathSize = NSMakeSize(
		kTableCellCurvePathWidth, kTableCellCurvePathHeight);
	curve.strokeColor = color;
	curve.lineWidth = kTableCellCurveLineWidth;
	curve.scalesToFit = YES;
	[curve setNeedsDisplay:YES];
}

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
	NSDictionary *cellSpec = objc_getAssociatedObject(
		column, &kKeys[kColumnCellKey]);
	if (cellSpec[@"curve"]) text = @"";

	NSString *reuseId = [@"cell-" stringByAppendingString:column.identifier];
	LuaTableCellView *cell = (LuaTableCellView *)[tableView
		makeViewWithIdentifier:reuseId owner:self];
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

		if (cellSpec[@"secondary"]) {
			NSTextField *secondary = [NSTextField labelWithString:@""];
			secondary.font = [NSFont
				systemFontOfSize:kTableCellSecondaryFontSize];
			secondary.textColor = NSColor.secondaryLabelColor;
			secondary.lineBreakMode = NSLineBreakByTruncatingTail;
			[cell addSubview:secondary];
			cell.secondaryTextField = secondary;
		}

		if (cellSpec[@"curve"]) {
			LuaPathView *curve = [[LuaPathView alloc]
				initWithFrame:NSZeroRect];
			curve.hidden = YES;
			[cell addSubview:curve];
			cell.curveView = curve;
		}

		NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
		imageView.imageScaling = NSImageScaleProportionallyDown;
		imageView.contentTintColor = NSColor.secondaryLabelColor;
		[cell addSubview:imageView];
		cell.imageView = imageView;
	}
	cell.textField.stringValue = text;
	NSString *secondaryKey = cellSpec[@"secondary"];
	id secondaryValue = secondaryKey ? rowData[secondaryKey] : nil;
	cell.secondaryTextField.stringValue = secondaryValue
		? [secondaryValue description] : @"";
	BOOL semibold = [cellSpec[@"weight"] isEqual:@"semibold"];
	cell.textField.font = [NSFont systemFontOfSize:NSFont.systemFontSize
		weight:semibold ? NSFontWeightSemibold : NSFontWeightRegular];
	NSString *primaryColorKey = cellSpec[@"color"];
	NSString *primaryColor = primaryColorKey
		? [rowData[primaryColorKey] description] : nil;
	cell.textField.textColor = primaryColor
		? table_semantic_color(primaryColor) : NSColor.labelColor;
	NSString *secondaryColorKey = cellSpec[@"secondaryColor"];
	NSString *secondaryColor = secondaryColorKey
		? [rowData[secondaryColorKey] description] : nil;
	cell.secondaryTextField.textColor = secondaryColor
		? table_semantic_color(secondaryColor) : NSColor.secondaryLabelColor;
	NSString *curveKey = cellSpec[@"curve"];
	NSArray *curveValues = [rowData[curveKey] isKindOfClass:NSArray.class]
		? rowData[curveKey] : nil;
	NSString *curveColorKey = cellSpec[@"curveColor"];
	NSString *curveColor = curveColorKey
		? [rowData[curveColorKey] description] : nil;
	table_update_curve(cell.curveView, curveValues,
		table_semantic_color(curveColor));
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
	cell.secondaryTextField.alignment = cell.textField.alignment;
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
	lua_objc_pcall(callL, 3, 0, "table selection");
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
	lua_objc_pcall(callL, 3, 0, "table activation");
}

@end
