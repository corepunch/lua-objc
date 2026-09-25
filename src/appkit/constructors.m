/* Native constructors exported by the AppKit module. */
#import <QuartzCore/QuartzCore.h>

/* AppKit has no KVC property to exclude a container subtree from hit testing.
 * Keep the native NSView traversal and opt out before it visits descendants. */
@interface LuaStackView : NSView
@property(nonatomic) BOOL allowsHitTesting;
@end
@implementation LuaStackView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) _allowsHitTesting = YES;
	return self;
}
// Publish the same content measurement used by the stack layout engine to
// native hosts such as NSToolbar, which ask for intrinsic/fitting geometry.
- (NSSize)intrinsicContentSize {
	if (!objc_getAssociatedObject(self, &kToolbarContentKey) || layout_axis(self) == LayoutAxisNone) return [super intrinsicContentSize];
	return measure_view(self, (LuaLayoutConstraint){
		.widthMode = LuaMeasureUndefined, .heightMode = LuaMeasureUndefined });
}
- (NSSize)fittingSize {
	return objc_getAssociatedObject(self, &kToolbarContentKey) ? self.intrinsicContentSize : [super fittingSize];
}
- (NSView *)hitTest:(NSPoint)point { return _allowsHitTesting ? [super hitTest:point] : nil; }
- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	NSColor *color = self.backgroundColor;
	if (color) self.backgroundColor = color;
}
@end

static int bridge_hit_test_target(lua_State *L) {
	NSView *view = check_view(L, 1);
	NSView *target = check_view(L, 2);
	NSPoint point = NSMakePoint(luaL_checknumber(L, 3), luaL_checknumber(L, 4));
	lua_pushboolean(L, [view hitTest:point] == target);
	return 1;
}

static int bridge_AppKitControls_vstack(lua_State *L) {

	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVStack), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hstack(lua_State *L) {

	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHStack), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_flowStack(lua_State *L) {

	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisFlow), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_zstack(lua_State *L) {
	NSView *obj = [[LuaStackView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisZStack), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

@interface NSScrollView (LuaKeyboardScroll)
@property(nonatomic) BOOL scrollOnKeyboard;
@end
@implementation NSScrollView (LuaKeyboardScroll)
- (BOOL)scrollOnKeyboard {
	return [objc_getAssociatedObject(self, &kKeys[kScrollOnKeyboardKey]) boolValue];
}
- (void)setScrollOnKeyboard:(BOOL)value {
	objc_setAssociatedObject(self, &kKeys[kScrollOnKeyboardKey], @(value),
		OBJC_ASSOCIATION_RETAIN);
}
@end

static int bridge_AppKitControls_scrollView(lua_State *L) {
	NSView *content = check_view(L, 1);
	CGFloat contentWidth = (CGFloat)luaL_optnumber(L, 2, 0);
	CGFloat contentHeight = (CGFloat)luaL_optnumber(L, 3, 0);

	NSScrollView *obj = [[LuaScrollView alloc] initWithFrame:NSZeroRect];
	obj.clipsToBounds = YES;
	obj.contentView.clipsToBounds = YES;
	obj.autohidesScrollers = YES;
	obj.borderType = NSNoBorder;
	obj.drawsBackground = NO;
	obj.documentView = content;
	objc_setAssociatedObject(obj, &kKeys[kScrollContentKey], content, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	/* Assigning documentView can restore AppKit's default vertical scroller;
	 * apply the requested axis policy after the document is installed. */
	obj.hasHorizontalScroller = YES;
	obj.hasVerticalScroller = NO;
	if (contentWidth > 0 || contentHeight > 0) {
		NSRect frame = content.frame;
		frame.size.width = contentWidth > 0 ? contentWidth : frame.size.width;
		frame.size.height = contentHeight > 0 ? contentHeight : frame.size.height;
		content.frame = frame;
		layout_recursive(content, frame.size.width);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hsplit(lua_State *L) {

	NSSplitView *obj = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	obj.vertical = YES;
	obj.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHSplit), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_vsplit(lua_State *L) {

	NSSplitView *obj = [[NSSplitView alloc] initWithFrame:NSZeroRect];
	obj.vertical = NO;
	obj.dividerStyle = NSSplitViewDividerStyleThin;
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVSplit), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_separator(lua_State *L) {

	NSBox *obj = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, kSeparatorSize, kSeparatorSize)];
	obj.boxType = NSBoxSeparator;
	objc_setAssociatedObject(obj, &kKeys[kFixedHeightKey], @(kSeparatorSize), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFillWidthKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_spacer(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSpacerSize, kSpacerSize)];
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexBasisKey], @0, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

@interface LuaGradientView : NSView
@property(nonatomic, strong) CAGradientLayer *gradient;
@end

@implementation LuaGradientView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		self.layer = [CALayer layer];
		self.layer.masksToBounds = YES;
	}
	return self;
}
- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.gradient.frame = self.bounds;
}
- (NSView *)hitTest:(NSPoint)point { return nil; }
@end

static int bridge_AppKitControls_linearGradient(lua_State *L) {
	CGFloat topAlpha = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat middleAlpha = (CGFloat)luaL_optnumber(L, 2, 0.5);
	CGFloat middleLocation = (CGFloat)luaL_optnumber(L, 3, 0.6);
	CGFloat bottomAlpha = (CGFloat)luaL_optnumber(L, 4, 0.82);
	LuaGradientView *view = [[LuaGradientView alloc] initWithFrame:NSZeroRect];
	CAGradientLayer *gradient = [CAGradientLayer layer];
	gradient.colors = @[(id)[NSColor colorWithWhite:0 alpha:topAlpha].CGColor,
		(id)[NSColor colorWithWhite:0 alpha:topAlpha].CGColor,
		(id)[NSColor colorWithWhite:0 alpha:middleAlpha].CGColor,
		(id)[NSColor colorWithWhite:0 alpha:bottomAlpha].CGColor];
	gradient.locations = @[@0.0, @0.3, @(middleLocation), @1.0];
	gradient.startPoint = CGPointMake(0.5, 1);
	gradient.endPoint = CGPointMake(0.5, 0);
	view.gradient = gradient;
	[view.layer addSublayer:gradient];
	push_objc(L, view, "nsview");
	return 1;
}

static int bridge_AppKitControls_label(lua_State *L) {
	push_objc(L, [LuaLabel wrappingLabelWithString:@""], "nsview");
	return 1;
}

static int bridge_AppKitControls_textField(lua_State *L) {

	LuaTextField *obj = [[LuaTextField alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_secureTextField(lua_State *L) {
	LuaSecureTextField *obj = [[LuaSecureTextField alloc]
		initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_searchField(lua_State *L) {
	NSSearchField *obj = [[NSSearchField alloc] initWithFrame:NSZeroRect];
	obj.bezelStyle = NSTextFieldRoundedBezel;
	obj.bezeled = YES;
	obj.drawsBackground = YES;
	[obj sizeToFit];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_box(lua_State *L) {

	NSBox *obj = [[NSBox alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_progressIndicator(lua_State *L) {

	NSProgressIndicator *obj = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_tableCellView(lua_State *L) {

	NSTableCellView *obj = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_popUpButton(lua_State *L) {

	NSPopUpButton *obj = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
	push_objc(L, obj, "nsview");
	return 1;
}

@interface LuaPopupMenuTarget : NSObject
@property(nonatomic, strong) NSArray *callbacks;
@end

@implementation LuaPopupMenuTarget
- (void)onAction:(NSPopUpButton *)sender {
	NSInteger index = sender.indexOfSelectedItem;
	if (index <= 0 || index > (NSInteger)self.callbacks.count) return;
	id callback = self.callbacks[index - 1];
	if (![callback isKindOfClass:LuaReg.class]) return;
	lua_State *L = lua_reg_live_state(callback);
	if (L && lua_reg_push(callback))
		lua_objc_pcall(L, 0, 0, "menu");
}
- (void)dealloc {
	for (id callback in _callbacks)
		if ([callback isKindOfClass:LuaReg.class]) [callback dispose];
}
@end

static int bridge_AppKitControls_menu(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	const char *title = luaL_optstring(L, 2, "Menu");
	const char *systemImage = luaL_optstring(L, 3, "");
	CGFloat symbolSize = (CGFloat)luaL_optnumber(L, 4, kDefaultSymbolPointSize);
	if (symbolSize <= 0) return luaL_error(L, "menu symbolSize must be positive");
	NSPopUpButton *button = [[NSPopUpButton alloc]
		initWithFrame:NSZeroRect pullsDown:YES];
	button.bordered = NO;
	[button removeAllItems];
	[button addItemWithTitle:[NSString stringWithUTF8String:title]];
	if (systemImage[0]) {
		NSImage *image = [NSImage imageWithSystemSymbolName:
			[NSString stringWithUTF8String:systemImage] accessibilityDescription:nil];
		[button itemAtIndex:0].image = [image imageWithSymbolConfiguration:
			[NSImageSymbolConfiguration configurationWithPointSize:symbolSize
				weight:NSFontWeightRegular]];
	}
	NSMutableArray *callbacks = [NSMutableArray array];
	NSInteger count = (NSInteger)luaL_len(L, 1);
	for (NSInteger index = 1; index <= count; index++) {
		lua_rawgeti(L, 1, index);
		lua_getfield(L, -1, "title");
		const char *itemTitle = luaL_optstring(L, -1, "");
		lua_pop(L, 1);
		[button addItemWithTitle:[NSString stringWithUTF8String:itemTitle]];
		NSMenuItem *item = [button itemAtIndex:index];
		lua_getfield(L, -1, "systemImage");
		const char *itemSymbol = luaL_optstring(L, -1, "");
		if (itemSymbol[0]) item.image = [NSImage imageWithSystemSymbolName:
			[NSString stringWithUTF8String:itemSymbol] accessibilityDescription:nil];
		lua_pop(L, 1);
		lua_getfield(L, -1, "action");
		LuaReg *callback = lua_reg_opt(L, -1);
		[callbacks addObject:callback ?: NSNull.null];
		if (!callback) item.enabled = NO;
		lua_pop(L, 2);
	}
	LuaPopupMenuTarget *target = [[LuaPopupMenuTarget alloc] init];
	target.callbacks = callbacks;
	button.target = target;
	button.action = @selector(onAction:);
	objc_setAssociatedObject(button, &kKeys[kCallbackKey], target,
		OBJC_ASSOCIATION_RETAIN);
	[button sizeToFit];
	push_objc(L, button, "nsview");
	return 1;
}

static void configure_control_callback(
	NSControl *control, lua_State *L, int callbackIndex
) {
	LuaReg *reg = lua_reg_opt(L, callbackIndex);
	if (!reg) return;
	lua_reg_store(control, &kKeys[kCallbackKey], reg);
	control.target = [LuaButtonTarget shared];
	control.action = @selector(onAction:);
}

static int bridge_AppKitControls_slider(lua_State *L) {
	CGFloat minimum = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat maximum = (CGFloat)luaL_optnumber(L, 2, 1);
	CGFloat value = (CGFloat)luaL_optnumber(L, 3, minimum);
	if (maximum < minimum) {
		return luaL_error(L, "Slider maximum must be greater than or equal to minimum");
	}

	NSSlider *slider = [[NSSlider alloc] initWithFrame:NSZeroRect];
	slider.minValue = minimum;
	slider.maxValue = maximum;
	slider.doubleValue = MIN(MAX(value, minimum), maximum);
	configure_control_callback(slider, L, 4);
	push_objc(L, slider, "nsview");
	return 1;
}

static int bridge_AppKitControls_stepper(lua_State *L) {
	CGFloat minimum = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat maximum = (CGFloat)luaL_optnumber(L, 2, 100);
	CGFloat increment = (CGFloat)luaL_optnumber(L, 3, 1);
	CGFloat value = (CGFloat)luaL_optnumber(L, 4, minimum);
	if (maximum < minimum || increment <= 0) {
		return luaL_error(L, "Stepper requires maximum >= minimum and increment > 0");
	}

	NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
	stepper.minValue = minimum;
	stepper.maxValue = maximum;
	stepper.increment = increment;
	stepper.doubleValue = MIN(MAX(value, minimum), maximum);
	configure_control_callback(stepper, L, 5);
	push_objc(L, stepper, "nsview");
	return 1;
}

static int bridge_AppKitControls_picker(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSInteger selectedIndex = (NSInteger)luaL_optinteger(L, 2, 0);
	id titles = lua_to_objc_value(L, 1);
	if (![titles isKindOfClass:[NSArray class]]) {
		return luaL_error(L, "Picker options must be an array");
	}

	NSPopUpButton *picker = [[NSPopUpButton alloc]
		initWithFrame:NSZeroRect pullsDown:NO];
	[picker addItemsWithTitles:titles];
	if (selectedIndex >= 0 && selectedIndex < picker.numberOfItems) {
		[picker selectItemAtIndex:selectedIndex];
	}
	configure_control_callback(picker, L, 3);
	push_objc(L, picker, "nsview");
	return 1;
}

static int bridge_AppKitControls_datePicker(lua_State *L) {
	NSDatePicker *picker = [[NSDatePicker alloc] initWithFrame:NSZeroRect];
	picker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
	picker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
	if (!lua_isnoneornil(L, 1))
		picker.dateValue = [NSDate dateWithTimeIntervalSince1970:luaL_checknumber(L, 1)];
	configure_control_callback(picker, L, 2);
	[picker sizeToFit];
	push_objc(L, picker, "nsview");
	return 1;
}

static int bridge_AppKitControls_colorPicker(lua_State *L) {
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:NSZeroRect];
	if (!lua_isnoneornil(L, 1))
		well.color = semantic_color([NSString stringWithUTF8String:luaL_checkstring(L, 1)]);
	configure_control_callback(well, L, 2);
	[well sizeToFit];
	push_objc(L, well, "nsview");
	return 1;
}

// NSButton owns tracking, keyboard activation, focus, and accessibility. Its
// declarative label must not intercept the native control's mouse events.
@interface LuaContentButton : NSButton
@end
@implementation LuaContentButton
- (NSView *)hitTest:(NSPoint)point { return [super hitTest:point] ? self : nil; }
@end

static int bridge_AppKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	NSView *content = lua_isnoneornil(L, 3) ? nil : check_view(L, 3);
	NSButton *obj = content ? [[LuaContentButton alloc] initWithFrame:NSZeroRect]
		: [[NSButton alloc] initWithFrame:NSZeroRect];
	obj.title = [NSString stringWithUTF8String:title];
	obj.bezelStyle = NSBezelStyleRounded;
	[obj sizeToFit];
	configure_control_callback(obj, L, 2);
	if (content) {
		[obj addSubview:content];
		objc_setAssociatedObject(obj, &kKeys[kButtonContentKey], content, OBJC_ASSOCIATION_RETAIN);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	const char *style = luaL_optstring(L, 4, "");

	/* System Settings rows use NSSwitch. A titled checkbox remains the default. */
	if (strcmp(style, "switch") == 0) {
		NSSwitch *control = [[NSSwitch alloc] initWithFrame:NSZeroRect];
		control.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
		if (label[0]) control.accessibilityLabel = [NSString stringWithUTF8String:label];
		[control sizeToFit];
		configure_control_callback(control, L, 3);
		push_objc(L, control, "nsview");
		return 1;
	}

	NSButton *obj = [NSButton checkboxWithTitle:[NSString stringWithUTF8String:label] target:nil action:nil];
	obj.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
	[obj sizeToFit];
	configure_control_callback(obj, L, 3);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_NSScrollView_onRefresh(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, obj, &kKeys[kTableRefreshKey], 2);
	return 0;
}

static int bridge_NSScrollView_onRowSelect(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, table_scrollview(obj), &kKeys[kTableSelectionKey], 2);
	return 0;
}

static int bridge_NSScrollView_onRowMove(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (![src isKindOfClass:[LuaTableViewSource class]])
		return luaL_error(L, "onRowMove requires a table view");
	NSScrollView *scroll = table_scrollview(obj);
	bridge_set_optional_callback(L, scroll, &kKeys[kTableMoveKey], 2);
	if (!lua_isnoneornil(L, 2)) {
		NSTableView *table = (NSTableView *)scroll.documentView;
		[table registerForDraggedTypes:@[NSPasteboardTypeString]];
		[table setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
	}
	return 0;
}

static int bridge_NSScrollView_onRowSwipe(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!source) return luaL_error(L, "onRowSwipe requires a table view");
	const char *edge = luaL_checkstring(L, 2);
	NSString *title = [NSString stringWithUTF8String:luaL_checkstring(L, 3)];
	BOOL destructive = strcmp(luaL_optstring(L, 4, "normal"), "destructive") == 0;
	(void)lua_toboolean(L, 5); // AppKit owns the row action's full-swipe behavior.
	LuaReg *callback = lua_reg_opt(L, 6);
	if (strcmp(edge, "leading") == 0) {
		source.leadingSwipeReg = callback;
		source.leadingSwipeTitle = title;
		source.leadingSwipeDestructive = destructive;
	} else if (strcmp(edge, "trailing") == 0) {
		source.trailingSwipeReg = callback;
		source.trailingSwipeTitle = title;
		source.trailingSwipeDestructive = destructive;
	} else return luaL_error(L, "swipe edge must be leading or trailing");
	return 0;
}

static int bridge_test_row_swipe(lua_State *L) {
	id obj = check_objc(L, 1);
	LuaTableViewSource *source = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!source) return luaL_error(L, "row swipe test requires a table view");
	NSInteger row = (NSInteger)luaL_checkinteger(L, 2) - 1;
	const char *edge = luaL_checkstring(L, 3);
	if (strcmp(edge, "leading") != 0 && strcmp(edge, "trailing") != 0)
		return luaL_error(L, "swipe edge must be leading or trailing");
	lua_pushboolean(L, [source invokeSwipeAtRow:row leading:strcmp(edge, "leading") == 0]);
	return 1;
}

static int bridge_NSScrollView_onColumnButton(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, table_scrollview(obj), &kKeys[kTableColumnButtonKey], 2);
	return 0;
}

static int bridge_NSScrollView_onColumnSort(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	bridge_set_optional_callback(L, table_scrollview(obj), &kKeys[kTableSortKey], 2);
	return 0;
}

static int bridge_NSScrollView_setSortIndicator(lua_State *L) {
	id obj = check_objc(L, 1);
	if (!objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]))
		return luaL_error(L, "not a table view");
	NSScrollView *scroll = table_scrollview(obj);
	NSTableView *table = (NSTableView *)scroll.documentView;
	NSString *identifier = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	BOOL ascending = lua_toboolean(L, 3);
	NSTableColumn *target = nil;
	for (NSTableColumn *column in table.tableColumns) {
		[table setIndicatorImage:nil inTableColumn:column];
		if ([column.identifier isEqualToString:identifier]) target = column;
	}
	if (target) {
		NSString *name = ascending ? @"NSAscendingSortIndicator" : @"NSDescendingSortIndicator";
		[table setIndicatorImage:[NSImage imageNamed:name] inTableColumn:target];
	}
	return 0;
}

static int bridge_pathView(lua_State *L) {
	CGFloat w = (CGFloat)luaL_optnumber(L, 1, 100);
	CGFloat h = (CGFloat)luaL_optnumber(L, 2, 100);
	LuaPathView *obj = [[LuaPathView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_NSScrollView_onRowActivate(lua_State *L) {
	id obj = check_objc(L, 1);
	id src = objc_getAssociatedObject(obj, &kKeys[kTableSourceKey]);
	if (!src) return luaL_error(L, "not a table or outline view");
	NSScrollView *sv = table_scrollview(obj);
	NSTableView *table = (NSTableView *)sv.documentView;
	BOOL hasCallback = !lua_isnoneornil(L, 2);
	table.target = hasCallback ? src : nil;
	table.doubleAction = hasCallback ? @selector(activateSelectedRow:) : nil;
	bridge_set_optional_callback(L, sv, &kKeys[kTableActivationKey], 2);
	return 0;
}
