#pragma mark - Native tab containers

@interface LuaRoundedTabItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, strong) NSView *view;
@end

@implementation LuaRoundedTabItem
@end

/*
 * The rounded editor tabs deliberately do not use NSTabView. The native
 * segmented control owns tab interaction while this ordinary NSView owns and
 * lays out the selected content child.
 */
@interface LuaRoundedTabContainer : NSView
@property (nonatomic, strong) NSSegmentedControl *tabSelector;
@property (nonatomic, strong) NSBox *tabSeparator;
@property (nonatomic, strong) NSMutableArray<LuaRoundedTabItem *> *items;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) int selectionRef;
@property (nonatomic, strong) LuaStateOwner *owner;
- (LuaRoundedTabItem *)addTabWithLabel:(NSString *)label view:(NSView *)view;
- (void)selectTabAtIndex:(NSInteger)index notify:(BOOL)notify;
- (void)removeTabAtIndex:(NSInteger)index;
@end

@implementation LuaRoundedTabContainer
- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_items = [NSMutableArray array];
		_selectedIndex = NSNotFound;
		_selectionRef = LUA_NOREF;
		_tabSelector = [[NSSegmentedControl alloc]
			initWithFrame:NSMakeRect(
				kRoundedTabHorizontalInset,
				kRoundedTabVerticalInset,
				MAX(0, frameRect.size.width -
					2 * kRoundedTabHorizontalInset),
				kRoundedTabControlHeight)];
		_tabSelector.segmentStyle = NSSegmentStyleCapsule;
		_tabSelector.segmentDistribution = NSSegmentDistributionFillEqually;
		_tabSelector.trackingMode = NSSegmentSwitchTrackingSelectOne;
		_tabSelector.controlSize = NSControlSizeRegular;
		_tabSelector.font = [NSFont systemFontOfSize:kRoundedTabFontSize];
		_tabSelector.target = self;
		_tabSelector.action = @selector(selectRoundedTab:);
		[self addSubview:_tabSelector
			positioned:NSWindowAbove
			relativeTo:nil];
		_tabSeparator = [[NSBox alloc] initWithFrame:NSMakeRect(
			0, MAX(0, frameRect.size.height -
				kRoundedTabBarHeight - kSeparatorSize),
			frameRect.size.width, kSeparatorSize)];
		_tabSeparator.boxType = NSBoxSeparator;
		[self addSubview:_tabSeparator
			positioned:NSWindowBelow
			relativeTo:_tabSelector];
	}
	return self;
}

- (void)dealloc {
	if (_selectionRef != LUA_NOREF && gL) {
		luaL_unref(gL, LUA_REGISTRYINDEX, _selectionRef);
		_selectionRef = LUA_NOREF;
	}
}

- (void)layout {
	[super layout];
	NSRect bounds = self.bounds;
	CGFloat barHeight = MIN(kRoundedTabBarHeight, bounds.size.height);
	_tabSelector.frame = NSMakeRect(
		kRoundedTabHorizontalInset,
		MAX(0, bounds.size.height - kRoundedTabBarHeight +
			kRoundedTabVerticalInset),
		MAX(0, bounds.size.width - 2 * kRoundedTabHorizontalInset),
		MIN(kRoundedTabControlHeight, barHeight));
	_tabSeparator.frame = NSMakeRect(
		0,
		MAX(0, bounds.size.height - barHeight - kSeparatorSize),
		bounds.size.width,
		kSeparatorSize);

	NSRect contentFrame = NSMakeRect(
		0, 0, bounds.size.width,
		MAX(0, bounds.size.height - barHeight - kSeparatorSize));
	for (LuaRoundedTabItem *item in _items) {
		item.view.frame = contentFrame;
	}
	[self addSubview:_tabSeparator
		positioned:NSWindowBelow
		relativeTo:_tabSelector];
	[self addSubview:_tabSelector
		positioned:NSWindowAbove
		relativeTo:nil];
}

- (void)reloadTabSelector {
	NSInteger count = _items.count;
	_tabSelector.segmentCount = count;
	for (NSInteger idx = 0; idx < count; idx++) {
		LuaRoundedTabItem *item = _items[idx];
		NSString *label = item.label ?: @"";
		[_tabSelector setLabel:label forSegment:idx];
		[_tabSelector setToolTip:label forSegment:idx];
	}
	if (_selectedIndex >= 0 && _selectedIndex < count) {
		_tabSelector.selectedSegment = _selectedIndex;
	}
	_tabSelector.hidden = count == 0;
	[self setNeedsLayout:YES];
}

- (LuaRoundedTabItem *)addTabWithLabel:(NSString *)label view:(NSView *)view {
	LuaRoundedTabItem *item = [[LuaRoundedTabItem alloc] init];
	item.identifier = [NSUUID UUID].UUIDString;
	item.label = label;
	item.view = view;
	view.hidden = YES;
	[_items addObject:item];
	[self addSubview:view positioned:NSWindowBelow relativeTo:_tabSelector];
	[self reloadTabSelector];
	[self selectTabAtIndex:_items.count - 1 notify:YES];
	return item;
}

- (void)removeTabAtIndex:(NSInteger)index {
	if (index < 0 || index >= _items.count) return;
	LuaRoundedTabItem *removed = _items[index];
	[removed.view removeFromSuperview];
	[_items removeObjectAtIndex:index];
	if (_items.count == 0) {
		_selectedIndex = NSNotFound;
	} else {
		NSInteger next = MIN(index, (NSInteger)_items.count - 1);
		[self selectTabAtIndex:next notify:YES];
	}
	[self reloadTabSelector];
}

- (void)selectTabAtIndex:(NSInteger)index notify:(BOOL)notify {
	if (index < 0 || index >= _items.count) return;
	_selectedIndex = index;
	for (NSInteger idx = 0; idx < _items.count; idx++) {
		_items[idx].view.hidden = idx != index;
	}
	_tabSelector.selectedSegment = index;
	[self setNeedsLayout:YES];

	if (!notify || _selectionRef == LUA_NOREF || !gL) return;
	LuaRoundedTabItem *item = _items[index];
	lua_State *L = gL;
	int top = lua_gettop(L);
	lua_rawgeti(L, LUA_REGISTRYINDEX, _selectionRef);
	push_objc(L, self, "nsview");
	lua_pushinteger(L, index);
	lua_pushstring(L, item.identifier.UTF8String);
	push_objc(L, item.view, "nsview");
	if (lua_pcall(L, 4, 0, 0) != LUA_OK) {
		fprintf(stderr, "tab selection error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	lua_settop(L, top);
}

- (void)selectRoundedTab:(NSSegmentedControl *)sender {
	[self selectTabAtIndex:sender.selectedSegment notify:YES];
}
@end

@interface LuaTabViewDelegate : NSObject <NSTabViewDelegate>
@property (nonatomic, assign) int selectionRef;
@property (nonatomic, strong) LuaStateOwner *owner;
@end

@implementation LuaTabViewDelegate
- (void)dealloc {
	if (_selectionRef != LUA_NOREF && gL) {
		luaL_unref(gL, LUA_REGISTRYINDEX, _selectionRef);
		_selectionRef = LUA_NOREF;
	}
}
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	if (_selectionRef == LUA_NOREF || !gL) return;
	lua_State *L = gL;
	int top = lua_gettop(L);
	lua_rawgeti(L, LUA_REGISTRYINDEX, _selectionRef);
	push_objc(L, tabView, "nsview");
	lua_pushinteger(L, [tabView indexOfTabViewItem:tabViewItem]);
	NSString *ident = tabViewItem.identifier;
	lua_pushstring(L, ident ? ident.UTF8String : "");
	if ([tabViewItem.view isKindOfClass:[NSView class]]) {
		push_objc(L, tabViewItem.view, "nsview");
	} else {
		lua_pushnil(L);
	}
	if (lua_pcall(L, 4, 0, 0) != LUA_OK) {
		fprintf(stderr, "tab selection error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	lua_settop(L, top);
}
@end

static id check_tab_container(lua_State *L, int index) {
	id obj = check_objc(L, index);
	if ([obj isKindOfClass:[LuaRoundedTabContainer class]]) return obj;
	return lua_objc_check_object(
		L, index, [NSTabView class], "NSTabView or LuaRoundedTabContainer");
}

static int bridge_tabview(lua_State *L) {
	CGFloat width = luaL_optnumber(L, 1, 400);
	CGFloat height = luaL_optnumber(L, 2, 200);

	const char *style = luaL_optstring(L, 3, "top");
	if (strcmp(style, "rounded") == 0) {
		LuaRoundedTabContainer *container = [[LuaRoundedTabContainer alloc]
			initWithFrame:NSMakeRect(0, 0, width, height)];
		push_objc(L, container, "nsview");
		return 1;
	}

	NSTabView *tv = [[NSTabView alloc] initWithFrame:
		NSMakeRect(0, 0, width, height)];
	if (strcmp(style, "top") == 0)
		tv.tabViewType = NSTopTabsBezelBorder;
	else if (strcmp(style, "bottom") == 0)
		tv.tabViewType = NSBottomTabsBezelBorder;
	else if (strcmp(style, "notabs") == 0)
		tv.tabViewType = NSNoTabsNoBorder;

	push_objc(L, tv, "nsview");
	return 1;
}

static int bridge_tab_add(lua_State *L) {
	id obj = check_tab_container(L, 1);
	const char *titleC = luaL_checkstring(L, 2);
	NSView *content = check_view(L, 3);

	NSString *title = [NSString stringWithUTF8String:titleC];
	if ([obj isKindOfClass:[LuaRoundedTabContainer class]]) {
		LuaRoundedTabItem *item =
			[(LuaRoundedTabContainer *)obj addTabWithLabel:title view:content];
		push_objc(L, item, "nsobject");
		return 1;
	}
	NSTabView *tv = (NSTabView *)obj;
	NSTabViewItem *item = [[NSTabViewItem alloc]
		initWithIdentifier:[NSUUID UUID].UUIDString];
	item.label = title;
	item.view = content;

	[tv addTabViewItem:item];
	[tv selectTabViewItem:item];

	push_objc(L, item, "nsobject");
	return 1;
}

static int bridge_tab_select(lua_State *L) {
	id obj = check_tab_container(L, 1);
	NSInteger idx = (NSInteger)luaL_checkinteger(L, 2);

	if ([obj isKindOfClass:[LuaRoundedTabContainer class]]) {
		[(LuaRoundedTabContainer *)obj selectTabAtIndex:idx notify:YES];
		return 0;
	}
	NSTabView *tv = (NSTabView *)obj;
	if (idx >= 0 && idx < (NSInteger)tv.numberOfTabViewItems) {
		[tv selectTabViewItemAtIndex:idx];
	}
	return 0;
}

static int bridge_tab_remove(lua_State *L) {
	id obj = check_tab_container(L, 1);
	NSInteger idx = (NSInteger)luaL_checkinteger(L, 2);

	if ([obj isKindOfClass:[LuaRoundedTabContainer class]]) {
		[(LuaRoundedTabContainer *)obj removeTabAtIndex:idx];
		return 0;
	}
	NSTabView *tv = (NSTabView *)obj;
	if (idx >= 0 && idx < (NSInteger)tv.numberOfTabViewItems) {
		NSTabViewItem *item = [tv tabViewItemAtIndex:idx];
		[tv removeTabViewItem:item];
	}
	return 0;
}

static int bridge_tab_count(lua_State *L) {
	id obj = check_tab_container(L, 1);
	if ([obj isKindOfClass:[LuaRoundedTabContainer class]]) {
		lua_pushinteger(L, ((LuaRoundedTabContainer *)obj).items.count);
		return 1;
	}
	lua_pushinteger(L, ((NSTabView *)obj).numberOfTabViewItems);
	return 1;
}

static int bridge_tab_on_change(lua_State *L) {
	id obj = check_tab_container(L, 1);
	int has_action = !lua_isnoneornil(L, 2);
	int ref = LUA_NOREF;

	if ([obj isKindOfClass:[LuaRoundedTabContainer class]]) {
		LuaRoundedTabContainer *container = obj;
		if (container.selectionRef != LUA_NOREF) {
			luaL_unref(L, LUA_REGISTRYINDEX, container.selectionRef);
			container.selectionRef = LUA_NOREF;
		}
		if (has_action) {
			luaL_checktype(L, 2, LUA_TFUNCTION);
			lua_pushvalue(L, 2);
			container.selectionRef = luaL_ref(L, LUA_REGISTRYINDEX);
			container.owner = owner_for_state(L);
		}
		return 0;
	}
	NSTabView *tv = (NSTabView *)obj;
	LuaTabViewDelegate *existing = objc_getAssociatedObject(
		tv, &kKeys[kTabViewDelegateKey]);
	if (existing) {
		tv.delegate = nil;
	}

	if (has_action) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);

		LuaTabViewDelegate *delegate = [[LuaTabViewDelegate alloc] init];
		delegate.owner = owner_for_state(L);
		delegate.selectionRef = ref;
		tv.delegate = delegate;
		objc_setAssociatedObject(tv, &kKeys[kTabViewDelegateKey],
			delegate, OBJC_ASSOCIATION_RETAIN);
	}
	return 0;
}

#pragma mark - NSSegmentedControl bridge (navigator tabs)

static int bridge_segmented_control(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSInteger selectedIdx = (NSInteger)luaL_optinteger(L, 2, 0);
	int has_action = !lua_isnoneornil(L, 3);
	int ref = LUA_NOREF;

	NSInteger count = (NSInteger)luaL_len(L, 1);
	if (count < 1) {
		lua_pushnil(L);
		return 1;
	}

	NSSegmentedControl *seg = [[NSSegmentedControl alloc]
		initWithFrame:NSMakeRect(0, 0, (CGFloat)count * 28, 28)];
	seg.segmentCount = count;
	seg.trackingMode = NSSegmentSwitchTrackingSelectOne;
	seg.segmentStyle = NSSegmentStyleCapsule;
	seg.segmentDistribution = NSSegmentDistributionFillEqually;

	NSImageSymbolConfiguration *symConfig =
		[NSImageSymbolConfiguration configurationWithPointSize:13
			weight:NSFontWeightMedium];

	for (NSInteger i = 0; i < count; i++) {
		lua_rawgeti(L, 1, (int)(i + 1));
		luaL_checktype(L, -1, LUA_TTABLE);
		lua_rawgeti(L, -1, 1);
		lua_rawgeti(L, -2, 2);
		const char *symbolC = lua_tostring(L, -2);
		const char *tipC = lua_tostring(L, -1);

		[seg setWidth:28 forSegment:i];
		if (symbolC) {
			NSString *name = [NSString stringWithUTF8String:symbolC];
			NSImage *img = [NSImage imageWithSystemSymbolName:name
				accessibilityDescription:nil];
			if (img) {
				img = [img imageWithSymbolConfiguration:symConfig];
				[seg setImage:img forSegment:i];
			}
		}
		if (tipC) {
			[seg setToolTip:[NSString stringWithUTF8String:tipC]
				forSegment:i];
		}
		lua_pop(L, 2);
		[seg setSelected:(i == selectedIdx) forSegment:i];
	}

	if (has_action) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		ref = luaL_ref(L, LUA_REGISTRYINDEX);
		objc_setAssociatedObject(seg, &kKeys[kCallbackKey], @(ref),
			OBJC_ASSOCIATION_RETAIN);
		seg.target = [LuaButtonTarget shared];
		seg.action = @selector(onAction:);
	}

	push_objc(L, seg, "nsview");
	return 1;
}
