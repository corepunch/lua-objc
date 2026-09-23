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
@property (nonatomic, strong) NSLevelIndicator *levelIndicator;
@property (nonatomic) CGFloat imageWidth;
@property (nonatomic, strong) NSProgressIndicator *loadingIndicator;
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
	if (_levelIndicator) {
		CGFloat height = ceil(text.intrinsicContentSize.height);
		text.frame = NSMakeRect(0, floor((self.bounds.size.height - height) / 2), kTableCellLevelTextWidth, height);
		CGFloat x = kTableCellLevelTextWidth + kTableCellLevelGap;
		_levelIndicator.frame = NSMakeRect(x, floor((self.bounds.size.height - kTableCellLevelHeight) / 2), MAX(0, self.bounds.size.width - x - kTableCellTextTrailingInset), kTableCellLevelHeight);
		return;
	}
	NSImageView *image = self.imageView;
	CGFloat imageWidth = image.image ? (_imageWidth > 0 ? _imageWidth : kTableCellImageWidth) : 0;
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
	if (_loadingIndicator && !_loadingIndicator.hidden) {
		[_loadingIndicator sizeToFit];
		CGFloat indicatorWidth = MIN(_loadingIndicator.frame.size.width, MAX(0, self.bounds.size.width - textX));
		CGFloat available = MAX(0, self.bounds.size.width - textX - kTableCellTextTrailingInset - indicatorWidth - kTableCellLoadingGap);
		CGFloat labelWidth = MIN(ceil(text.fittingSize.width), available);
		CGFloat groupWidth = indicatorWidth + kTableCellLoadingGap + labelWidth;
		CGFloat x = textX;
		if (text.alignment == NSTextAlignmentRight) x = MAX(textX, self.bounds.size.width - kTableCellTextTrailingInset - groupWidth);
		else if (text.alignment == NSTextAlignmentCenter) x = MAX(textX, (self.bounds.size.width - groupWidth) / 2);
		_loadingIndicator.frame = NSMakeRect(x, floor((self.bounds.size.height - _loadingIndicator.frame.size.height) / 2), indicatorWidth, _loadingIndicator.frame.size.height);
		text.frame = NSMakeRect(x + indicatorWidth + kTableCellLoadingGap, textY, labelWidth, height);
	}
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

static NSColor *semantic_color(NSString *name);

// Shared symbol presentation for standalone images and reusable data cells.
@interface LuaSymbolImageView : NSImageView
@property(nonatomic) CGFloat symbolSize;
@property(nonatomic, copy) NSString *badgeColorName;
@property(nonatomic, copy) NSString *appBundleId;
@property(nonatomic) BOOL resolvedAppIcon;
@property(nonatomic, strong) NSColor *symbolTintColor;
@property(nonatomic, strong) NSImage *symbolImage;
@end
@implementation LuaSymbolImageView
- (void)setImage:(NSImage *)image {
	_symbolImage = image;
	[super setImage:image];
}
- (NSSize)intrinsicContentSize {
	if ((_badgeColorName.length || _resolvedAppIcon) && _symbolSize > 0) return NSMakeSize(_symbolSize, _symbolSize);
	return [super intrinsicContentSize];
}
- (void)setBadgeColorName:(NSString *)value {
	if (![self.contentTintColor isEqual:NSColor.whiteColor]) _symbolTintColor = self.contentTintColor;
	_badgeColorName = [value copy];
	self.contentTintColor = value.length ? NSColor.whiteColor : _symbolTintColor;
	[self invalidateIntrinsicContentSize];
	[self setNeedsDisplay:YES];
}
- (void)setAppBundleId:(NSString *)value {
	_appBundleId = [value copy];
	NSURL *url = value.length ? [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:value] : nil;
	_resolvedAppIcon = url != nil;
	[self invalidateIntrinsicContentSize];
	if (url) {
		[super setImage:[NSWorkspace.sharedWorkspace iconForFile:url.path]];
		self.contentTintColor = nil;
	} else {
		[super setImage:_symbolImage];
		self.contentTintColor = _badgeColorName.length ? NSColor.whiteColor : _symbolTintColor;
	}
	[self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
	BOOL badge = _badgeColorName.length && !_resolvedAppIcon && self.image;
	if (!badge) { [super drawRect:dirtyRect]; return; }
	[semantic_color(_badgeColorName) setFill];
	CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * kIconBadgeCornerFraction;
	[[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
	[NSGraphicsContext saveGraphicsState];
	NSAffineTransform *transform = [NSAffineTransform transform];
	[transform translateXBy:NSMidX(self.bounds) yBy:NSMidY(self.bounds)];
	[transform scaleBy:kIconBadgeSymbolScale];
	[transform translateXBy:-NSMidX(self.bounds) yBy:-NSMidY(self.bounds)];
	[transform concat];
	[super drawRect:self.bounds];
	[NSGraphicsContext restoreGraphicsState];
}
@end

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

static NSView *table_cell_view(NSTableView *tableView, NSTableColumn *column, NSDictionary *rowData, id owner) {

	NSString *colId = column.identifier;
	id value = rowData[colId];
	NSString *text = value ? [value description] : @"";
	NSDictionary *cellSpec = objc_getAssociatedObject(
		column, &kKeys[kColumnCellKey]);
	if (cellSpec[@"curve"]) text = @"";

	NSString *reuseId = [@"cell-" stringByAppendingString:column.identifier];
	LuaTableCellView *cell = (LuaTableCellView *)[tableView
		makeViewWithIdentifier:reuseId owner:owner];
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

		// Table delegates own cell content; a row-bound native indicator must be
		// configured here so reuse clears animation along with the text.
		if (cellSpec[@"loading"]) {
			NSProgressIndicator *indicator = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
			indicator.style = NSProgressIndicatorStyleSpinning;
			indicator.controlSize = NSControlSizeSmall;
			indicator.indeterminate = YES;
			indicator.displayedWhenStopped = NO;
			[indicator sizeToFit];
			[cell addSubview:indicator];
			cell.loadingIndicator = indicator;
		}
		// Reusable native table cells own their embedded Cocoa controls.
		if (cellSpec[@"level"]) {
			NSLevelIndicator *level = [[NSLevelIndicator alloc] initWithFrame:NSZeroRect];
			level.levelIndicatorStyle = NSLevelIndicatorStyleContinuousCapacity;
			level.warningValue = 2;
			level.criticalValue = 2;
			level.minValue = 0;
			level.maxValue = 1;
			level.editable = NO;
			[cell addSubview:level];
			cell.levelIndicator = level;
		}
		if (cellSpec[@"curve"]) {
			LuaPathView *curve = [[LuaPathView alloc]
				initWithFrame:NSZeroRect];
			curve.hidden = YES;
			[cell addSubview:curve];
			cell.curveView = curve;
		}

		NSImageView *imageView = [[LuaSymbolImageView alloc] initWithFrame:NSZeroRect];
		imageView.imageScaling = NSImageScaleProportionallyDown;
		imageView.contentTintColor = NSColor.secondaryLabelColor;
		[cell addSubview:imageView];
		cell.imageView = imageView;
	}
	cell.imageWidth = [cellSpec[@"imageSize"] doubleValue];
	cell.textField.stringValue = text;
	NSString *secondaryKey = cellSpec[@"secondary"];
	id secondaryValue = secondaryKey ? rowData[secondaryKey] : nil;
	cell.secondaryTextField.stringValue = secondaryValue
		? [secondaryValue description] : @"";
	BOOL semibold = [cellSpec[@"weight"] isEqual:@"semibold"];
	BOOL small = [cellSpec[@"controlSize"] isEqual:@"small"];
	cell.textField.font = [NSFont systemFontOfSize:small ? NSFont.smallSystemFontSize : NSFont.systemFontSize
		weight:semibold ? NSFontWeightSemibold : NSFontWeightRegular];
	NSString *primaryColorKey = cellSpec[@"color"];
	NSString *primaryColor = primaryColorKey
		? [rowData[primaryColorKey] description] : nil;
	cell.textField.textColor = primaryColor
		? semantic_color(primaryColor) : NSColor.labelColor;
	NSString *loadingKey = cellSpec[@"loading"];
	BOOL loading = loadingKey && [rowData[loadingKey] respondsToSelector:@selector(boolValue)] && [rowData[loadingKey] boolValue];
	cell.loadingIndicator.hidden = !loading;
	if (loading) {
		[cell.loadingIndicator startAnimation:nil];
		cell.textField.textColor = NSColor.secondaryLabelColor;
	} else [cell.loadingIndicator stopAnimation:nil];
	NSString *secondaryColorKey = cellSpec[@"secondaryColor"];
	NSString *secondaryColor = secondaryColorKey
		? [rowData[secondaryColorKey] description] : nil;
	cell.secondaryTextField.textColor = secondaryColor
		? semantic_color(secondaryColor) : NSColor.secondaryLabelColor;
	NSString *curveKey = cellSpec[@"curve"];
	NSArray *curveValues = [rowData[curveKey] isKindOfClass:NSArray.class]
		? rowData[curveKey] : nil;
	NSString *curveColorKey = cellSpec[@"curveColor"];
	NSString *curveColor = curveColorKey
		? [rowData[curveColorKey] description] : nil;
	table_update_curve(cell.curveView, curveValues,
		semantic_color(curveColor));
	// Row-bound symbols let a native source list distinguish navigation destinations.
	NSString *levelKey = cellSpec[@"level"];
	id levelValue = levelKey ? rowData[levelKey] : nil;
	double fraction = [levelValue respondsToSelector:@selector(doubleValue)] ? [levelValue doubleValue] : 0;
	cell.levelIndicator.doubleValue = isfinite(fraction) ? MAX(0, MIN(1, fraction)) : 0;
	cell.levelIndicator.hidden = levelValue == nil;
	NSString *levelColorKey = cellSpec[@"levelColor"];
	cell.levelIndicator.fillColor = semantic_color(levelColorKey ? rowData[levelColorKey] : nil);
	cell.levelIndicator.accessibilityLabel = [@"Share of measured storage: " stringByAppendingString:text];
	[cell.levelIndicator setNeedsDisplay:YES];
	NSString *imageColorKey = cellSpec[@"imageColor"];
	cell.imageView.contentTintColor = imageColorKey ? semantic_color(rowData[imageColorKey]) : NSColor.secondaryLabelColor;
	NSString *imageKey = cellSpec[@"image"];
	NSString *symbolName = imageKey && [rowData[imageKey] isKindOfClass:NSString.class]
		? rowData[imageKey] : objc_getAssociatedObject(column, &kKeys[kColumnSystemImageKey]);
	NSString *fileKey = cellSpec[@"fileIcon"];
	NSString *filePath = fileKey && [rowData[fileKey] isKindOfClass:NSString.class] ? rowData[fileKey] : nil;
	if (filePath.length > 0) {
		cell.imageView.image = [NSWorkspace.sharedWorkspace iconForFile:filePath];
		cell.imageView.contentTintColor = nil;
	} else if (symbolName.length > 0) {
		NSImage *image = [NSImage imageWithSystemSymbolName:symbolName
			accessibilityDescription:text];
		NSImageSymbolConfiguration *configuration =
		[NSImageSymbolConfiguration configurationWithPointSize:(cell.imageWidth > 0 ? cell.imageWidth - 3 : kTableCellSymbolPointSize)
													 weight:NSFontWeightRegular];
		cell.imageView.image = [image imageWithSymbolConfiguration:configuration];
	} else {
		cell.imageView.image = nil;
	}
	LuaSymbolImageView *symbolView = (LuaSymbolImageView *)cell.imageView;
	symbolView.badgeColorName = cellSpec[@"badgeColor"] ? rowData[cellSpec[@"badgeColor"]] : nil;
	symbolView.appBundleId = cellSpec[@"appIcon"] ? rowData[cellSpec[@"appIcon"]] : nil;
	if (filePath.length) { symbolView.resolvedAppIcon = YES; symbolView.contentTintColor = nil; }
	NSNumber *alignment = objc_getAssociatedObject(column, &kKeys[kColumnAlignmentKey]);
	cell.textField.alignment = alignment
		? (NSTextAlignment)alignment.integerValue : NSTextAlignmentLeft;
	cell.secondaryTextField.alignment = cell.textField.alignment;
	[cell setNeedsLayout:YES];
	return cell;
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
	 * Native table styles apply row-cell insets, and NSTableView places
	 * inter-column spacing outside the declared widths.
	 * Measure both from AppKit's actual last-cell frame so fixed and flexible
	 * columns remain inside the clip view without duplicating system metrics.
	 */
	if (_rows.count == 0 || _tableView.tableColumns.count == 0) return 0;

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
		else tableWidth = viewport.width;
	}

	CGRect frame = _tableView.frame;
	frame.size.width = tableWidth;
	frame.size.height = MAX(viewport.height, rowsHeight);
	_tableView.frame = frame;

	NSScrollView *sv = _tableView.enclosingScrollView;
	sv.hasHorizontalScroller = overflows;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
	return table_cell_view(tableView, column, _rows[row], self);
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column {
	if (![objc_getAssociatedObject(column, &kKeys[kColumnSortableKey]) boolValue]) return;
	NSScrollView *scroll = tableView.enclosingScrollView;
	LuaReg *reg = objc_getAssociatedObject(scroll, &kKeys[kTableSortKey]);
	lua_State *callL = lua_reg_live_state(reg);
	if (!callL || !lua_reg_push(reg)) return;
	push_objc(callL, scroll, "nsview");
	lua_pushstring(callL, column.identifier.UTF8String);
	lua_objc_pcall(callL, 2, 0, "table column sort");
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
	LuaReg *reg = objc_getAssociatedObject(sv, &kKeys[kTableSelectionKey]);
	lua_State *callL = lua_reg_live_state(reg);
	if (!sv || !callL || !lua_reg_push(reg)) return;

	NSDictionary *rowData = _rows[row];
	push_objc(callL, sv, "nsview");
	lua_pushinteger(callL, (lua_Integer)row);
	lua_newtable(callL);
	for (NSString *key in rowData) {
		id value = rowData[key];
		push_objc_value(callL, value);
		lua_setfield(callL, -2, [key UTF8String]);
	}
	lua_objc_pcall(callL, 3, 0, "table selection");
}

- (void)activateSelectedRow:(id)sender {
	NSInteger row = _tableView.selectedRow;
	if (row < 0 || row >= (NSInteger)_rows.count) return;
	NSScrollView *sv = _tableView.enclosingScrollView;
	LuaReg *reg = objc_getAssociatedObject(sv, &kKeys[kTableActivationKey]);
	lua_State *callL = lua_reg_live_state(reg);
	if (!callL || !lua_reg_push(reg)) return;

	NSDictionary *rowData = _rows[row];
	push_objc(callL, sv, "nsview");
	lua_pushinteger(callL, (lua_Integer)row);
	lua_newtable(callL);
	for (NSString *key in rowData) {
		id value = rowData[key];
		push_objc_value(callL, value);
		lua_setfield(callL, -2, key.UTF8String);
	}
	lua_objc_pcall(callL, 3, 0, "table activation");
}

@end
