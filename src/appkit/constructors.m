/* Native constructors exported by the AppKit module. */

static int bridge_AppKitControls_vstack(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisVStack), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_hstack(lua_State *L) {

	NSView *obj = [[NSView alloc] initWithFrame:NSZeroRect];
	objc_setAssociatedObject(obj, &kKeys[kAxisKey], @(LayoutAxisHStack), OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_scrollView(lua_State *L) {
	NSView *content = check_view(L, 1);
	CGFloat contentWidth = (CGFloat)luaL_optnumber(L, 2, 0);
	CGFloat contentHeight = (CGFloat)luaL_optnumber(L, 3, 0);

	NSScrollView *obj = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	obj.autohidesScrollers = YES;
	obj.borderType = NSNoBorder;
	obj.drawsBackground = NO;
	obj.documentView = content;
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

static void configure_control_callback(
	NSControl *control, lua_State *L, int callbackIndex
) {
	int callbackRef;
	LUA_OPT_CALLBACK_REF(L, callbackIndex, callbackRef);
	if (callbackRef == LUA_NOREF) return;
	objc_setAssociatedObject(control, &kKeys[kCallbackKey], @(callbackRef),
		OBJC_ASSOCIATION_RETAIN);
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

static int bridge_AppKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	int callback_ref;
	LUA_OPT_CALLBACK_REF(L, 2, callback_ref);

	NSButton *obj = [[NSButton alloc] initWithFrame:NSZeroRect];
	obj.title = [NSString stringWithUTF8String:title];
	obj.bezelStyle = NSBezelStyleRounded;
	[obj sizeToFit];
	if (callback_ref != LUA_NOREF) {
		objc_setAssociatedObject(obj, &kKeys[kCallbackKey], @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		obj.target = [LuaButtonTarget shared];
		obj.action = @selector(onAction:);
	}
	push_objc(L, obj, "nsview");
	return 1;
}

static int bridge_AppKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	int callback_ref;
	LUA_OPT_CALLBACK_REF(L, 3, callback_ref);

	NSButton *obj = [NSButton checkboxWithTitle:[NSString stringWithUTF8String:label] target:nil action:nil];
	obj.state = is_on ? NSControlStateValueOn : NSControlStateValueOff;
	[obj sizeToFit];
	if (callback_ref != LUA_NOREF) {
		objc_setAssociatedObject(obj, &kKeys[kCallbackKey], @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		obj.target = [LuaButtonTarget shared];
		obj.action = @selector(onAction:);
	}
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
