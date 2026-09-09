#pragma mark - UITabBarController bridge

@interface LuaTabBarControllerDelegate : NSObject <UITabBarControllerDelegate>
@property (nonatomic, assign) int selectionRef;
@property (nonatomic, strong) LuaStateOwner *owner;
@end

@implementation LuaTabBarControllerDelegate
- (void)dealloc {
	lua_State *callL = _owner.L;
	if (_selectionRef != LUA_NOREF && callL) {
		luaL_unref(callL, LUA_REGISTRYINDEX, _selectionRef);
		_selectionRef = LUA_NOREF;
	}
}

- (void)tabBarController:(UITabBarController *)tabBarController
 didSelectViewController:(UIViewController *)viewController {
	lua_State *L = _owner.L;
	if (_selectionRef == LUA_NOREF || !L) return;
	int top = lua_gettop(L);
	lua_rawgeti(L, LUA_REGISTRYINDEX, _selectionRef);
	push_objc(L, tabBarController, "uiviewcontroller");
	lua_pushinteger(L,
		[tabBarController.viewControllers indexOfObject:viewController]);
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
		fprintf(stderr, "tab selection error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	lua_settop(L, top);
}
@end

static char kTabBarDelegateKey;

static int bridge_tabview(lua_State *L) {
	UITabBarController *tbc = [[UITabBarController alloc] init];
	push_objc(L, tbc, "uiviewcontroller");
	return 1;
}

static char kNavigationBarHiddenKey;

@interface LuaNavigationController : UINavigationController <UINavigationControllerDelegate>
@property(nonatomic, readonly) NSInteger depth;
@property(nonatomic, readonly) UIViewController *currentController;
@end
@implementation LuaNavigationController
- (NSInteger)depth { return self.viewControllers.count; }
- (UIViewController *)currentController { return self.topViewController; }
- (void)navigationController:(UINavigationController *)navigation willShowViewController:(UIViewController *)controller animated:(BOOL)animated {
	[navigation setNavigationBarHidden:[objc_getAssociatedObject(controller, &kNavigationBarHiddenKey) boolValue] animated:animated];
}
@end

static int bridge_UIKitNavigation_stack(lua_State *L) {
	UIViewController *root = check_view_controller(L, 1);
	LuaNavigationController *nav = [[LuaNavigationController alloc] initWithRootViewController:root];
	BOOL hidden = lua_toboolean(L, 2);
	objc_setAssociatedObject(root, &kNavigationBarHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN);
	nav.navigationBarHidden = hidden;
	nav.delegate = nav;
	push_objc(L, nav, "uiviewcontroller");
	return 1;
}

static int bridge_UIKitNavigation_push(lua_State *L) {
	UINavigationController *nav = (UINavigationController *)check_objc(L, 1);
	UIViewController *controller = check_view_controller(L, 2);
	const char *title = luaL_optstring(L, 3, "");
	if (title && title[0]) controller.title = [NSString stringWithUTF8String:title];
	[nav pushViewController:controller animated:NO];
	return 0;
}

static int bridge_UIKitNavigation_pop(lua_State *L) {
	UINavigationController *nav = (UINavigationController *)check_objc(L, 1);
	[nav popViewControllerAnimated:NO];
	return 0;
}

@interface LuaNavigationLinkTarget : NSObject
@property (nonatomic, weak) UINavigationController *navigation;
@property (nonatomic, strong) UIViewController *destination;
@end

@implementation LuaNavigationLinkTarget
- (void)onAction:(id)sender {
	if (self.navigation && self.destination)
		[self.navigation pushViewController:self.destination animated:NO];
}
@end

static int bridge_UIKitNavigation_link(lua_State *L) {
	UINavigationController *navigation =
		(UINavigationController *)check_objc(L, 1);
	UIViewController *destination = check_view_controller(L, 2);
	const char *title = luaL_optstring(L, 3, "");
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	[button setTitle:[NSString stringWithUTF8String:title]
		forState:UIControlStateNormal];
	LuaNavigationLinkTarget *target = [[LuaNavigationLinkTarget alloc] init];
	target.navigation = navigation;
	target.destination = destination;
	[button addTarget:target action:@selector(onAction:)
		forControlEvents:UIControlEventTouchUpInside];
	objc_setAssociatedObject(button, &kCallbackKey, target,
		OBJC_ASSOCIATION_RETAIN);
	[button sizeToFit];
	push_objc(L, button, "uiview");
	return 1;
}

static int bridge_UIKitTabView_addTab(lua_State *L) {
	id obj = check_objc(L, 1);
	UITabBarController *tbc = (UITabBarController *)obj;
	UIViewController *vc = check_view_controller(L, 2);
	const char *title = luaL_optstring(L, 3, "");
	const char *systemImage = luaL_optstring(L, 4, "");

	vc.tabBarItem = [[UITabBarItem alloc]
		initWithTitle:[NSString stringWithUTF8String:title]
		image:nil
		tag:(NSInteger)tbc.viewControllers.count];

	if (systemImage && strlen(systemImage) > 0) {
		vc.tabBarItem.image = [UIImage
			systemImageNamed:[NSString stringWithUTF8String:systemImage]];
	}

	NSMutableArray *children = [NSMutableArray arrayWithArray:tbc.viewControllers ?: @[]];
	[children addObject:vc];
	tbc.viewControllers = children;

	push_objc(L, vc, "uiviewcontroller");
	return 1;
}

static int bridge_UIKitTabView_selectTab(lua_State *L) {
	id obj = check_objc(L, 1);
	UITabBarController *tbc = (UITabBarController *)obj;
	NSInteger index = (NSInteger)luaL_checkinteger(L, 2);
	if (index >= 0 && index < (NSInteger)tbc.viewControllers.count) {
		tbc.selectedIndex = index;
	}
	return 0;
}

static int bridge_UIKitTabView_tabCount(lua_State *L) {
	id obj = check_objc(L, 1);
	UITabBarController *tbc = (UITabBarController *)obj;
	lua_pushinteger(L, (lua_Integer)tbc.viewControllers.count);
	return 1;
}

static int bridge_UIKitTabView_onChange(lua_State *L) {
	id obj = check_objc(L, 1);
	UITabBarController *tbc = (UITabBarController *)obj;
	int callback = luaL_ref(L, LUA_REGISTRYINDEX);

	LuaTabBarControllerDelegate *existing = objc_getAssociatedObject(
		tbc, &kTabBarDelegateKey);
	if (existing) {
		tbc.delegate = nil;
		objc_setAssociatedObject(tbc, &kTabBarDelegateKey, nil,
			OBJC_ASSOCIATION_RETAIN);
	}

	if (callback != LUA_NOREF) {
		LuaTabBarControllerDelegate *delegate =
			[[LuaTabBarControllerDelegate alloc] init];
		delegate.owner = owner_for_state(L);
		delegate.selectionRef = callback;
		tbc.delegate = delegate;
		objc_setAssociatedObject(tbc, &kTabBarDelegateKey,
			delegate, OBJC_ASSOCIATION_RETAIN);
	}
	return 0;
}
