#pragma mark - Native tab containers

static void configure_segmented_control(NSSegmentedControl *selector) {
	selector.trackingMode = NSSegmentSwitchTrackingSelectOne;
	selector.segmentDistribution = NSSegmentDistributionFillEqually;
	selector.segmentStyle = NSSegmentStyleAutomatic;
	selector.borderShape = NSControlBorderShapeCapsule;
}

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

static int bridge_tabview(lua_State *L) {
	CGFloat width = luaL_optnumber(L, 1, 400);
	CGFloat height = luaL_optnumber(L, 2, 200);

	const char *style = luaL_optstring(L, 3, "top");
	NSTabView *tv = [[NSTabView alloc] initWithFrame:
		NSMakeRect(0, 0, width, height)];
	if (strcmp(style, "top") == 0)
		tv.tabViewType = NSTopTabsBezelBorder;
	else if (strcmp(style, "bottom") == 0)
		tv.tabViewType = NSBottomTabsBezelBorder;
	else if (strcmp(style, "notabs") == 0)
		tv.tabViewType = NSNoTabsNoBorder;
	else
		return luaL_error(
			L, "tab view style must be 'top', 'bottom', or 'notabs'");

	push_objc(L, tv, "nsview");
	return 1;
}

/* ─── NSTabView method implementations ───────────────────────────────── */

static int bridge_NSTabView_addTab_impl(lua_State *L, NSTabView *self,
                                         const char *title,
                                         NSView *content) {
	NSString *titleStr = [NSString stringWithUTF8String:title];
	NSTabViewItem *item = [[NSTabViewItem alloc]
		initWithIdentifier:[NSUUID UUID].UUIDString];
	item.label = titleStr;
	item.view = content;

	[self addTabViewItem:item];
	[self selectTabViewItem:item];

	push_objc(L, item, "nsobject");
	return 1;
}

static int bridge_NSTabView_removeTab_impl(lua_State *L, NSTabView *self,
                                            NSInteger index) {
	if (index >= 0 && index < (NSInteger)self.numberOfTabViewItems) {
		NSTabViewItem *item = [self tabViewItemAtIndex:index];
		[self removeTabViewItem:item];
	}
	return 0;
}

static int bridge_NSTabView_selectTab_impl(lua_State *L, NSTabView *self,
                                            NSInteger index) {
	if (index >= 0 && index < (NSInteger)self.numberOfTabViewItems) {
		[self selectTabViewItemAtIndex:index];
	}
	return 0;
}

static int bridge_NSTabView_tabCount_impl(lua_State *L, NSTabView *self) {
	lua_pushinteger(L, (lua_Integer)self.numberOfTabViewItems);
	return 1;
}

static int bridge_NSTabView_onChange_impl(lua_State *L, NSTabView *self,
                                           int callback) {
	LuaTabViewDelegate *existing = objc_getAssociatedObject(
		self, &kKeys[kTabViewDelegateKey]);
	if (existing) {
		self.delegate = nil;
	}

	if (callback != LUA_NOREF) {
		LuaTabViewDelegate *delegate = [[LuaTabViewDelegate alloc] init];
		delegate.owner = owner_for_state(L);
		delegate.selectionRef = callback;
		self.delegate = delegate;
		objc_setAssociatedObject(self, &kKeys[kTabViewDelegateKey],
			delegate, OBJC_ASSOCIATION_RETAIN);
	}
	return 0;
}

#pragma mark - NSSegmentedControl bridge

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
	configure_segmented_control(seg);

	NSImageSymbolConfiguration *symConfig =
		[NSImageSymbolConfiguration configurationWithPointSize:13
			weight:NSFontWeightMedium];

	for (NSInteger i = 0; i < count; i++) {
		lua_rawgeti(L, 1, (int)(i + 1));
		NSArray *pair = lua_to_objc_value(L, -1);
		lua_pop(L, 1);
		NSString *symbol = pair[0];
		NSString *tip = pair[1];

		[seg setWidth:28 forSegment:i];
		if (symbol) {
			NSImage *img = [NSImage imageWithSystemSymbolName:symbol
				accessibilityDescription:nil];
			if (img) {
				img = [img imageWithSymbolConfiguration:symConfig];
				[seg setImage:img forSegment:i];
			}
		}
		if (tip) {
			[seg setToolTip:tip forSegment:i];
		}
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
