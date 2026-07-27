#pragma mark - NSTabView bridge

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

	NSTabView *tv = [[NSTabView alloc] initWithFrame:
		NSMakeRect(0, 0, width, height)];

	const char *style = luaL_optstring(L, 3, "top");
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
	NSTabView *tv = (NSTabView *)check_view(L, 1);
	const char *titleC = luaL_checkstring(L, 2);
	NSView *content = check_view(L, 3);

	NSString *title = [NSString stringWithUTF8String:titleC];
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
	NSTabView *tv = (NSTabView *)check_view(L, 1);
	NSInteger idx = (NSInteger)luaL_checkinteger(L, 2);

	if (idx >= 0 && idx < (NSInteger)tv.numberOfTabViewItems) {
		[tv selectTabViewItemAtIndex:idx];
	}
	return 0;
}

static int bridge_tab_remove(lua_State *L) {
	NSTabView *tv = (NSTabView *)check_view(L, 1);
	NSInteger idx = (NSInteger)luaL_checkinteger(L, 2);

	if (idx >= 0 && idx < (NSInteger)tv.numberOfTabViewItems) {
		NSTabViewItem *item = [tv tabViewItemAtIndex:idx];
		[tv removeTabViewItem:item];
	}
	return 0;
}

static int bridge_tab_count(lua_State *L) {
	NSTabView *tv = (NSTabView *)check_view(L, 1);
	lua_pushinteger(L, tv.numberOfTabViewItems);
	return 1;
}

static int bridge_tab_on_change(lua_State *L) {
	NSTabView *tv = (NSTabView *)check_view(L, 1);
	int has_action = !lua_isnoneornil(L, 2);
	int ref = LUA_NOREF;

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
