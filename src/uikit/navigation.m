#pragma mark - UITabBarController bridge

@interface LuaTabBarControllerDelegate : NSObject <UITabBarControllerDelegate>
@property (nonatomic, strong) LuaReg *selection;
@end

@implementation LuaTabBarControllerDelegate
- (void)dealloc {
	[_selection dispose];
}

- (void)tabBarController:(UITabBarController *)tabBarController
 didSelectViewController:(UIViewController *)viewController {
	lua_State *L = lua_reg_live_state(_selection);
	if (!L) return;
	int top = lua_gettop(L);
	if (!lua_reg_push(_selection)) return;
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
	const char *behavior = luaL_optstring(L, 1, "automatic");
	if (strcmp(behavior, "automatic") == 0)
		tbc.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorAutomatic;
	else if (strcmp(behavior, "never") == 0)
		tbc.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorNever;
	else if (strcmp(behavior, "onScroll") == 0
		|| strcmp(behavior, "onScrollDown") == 0)
		tbc.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
	else if (strcmp(behavior, "onScrollUp") == 0)
		tbc.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollUp;
	else
		return luaL_error(L, "minimizeBehavior must be 'automatic', 'never', 'onScroll', or 'onScrollUp'");
	push_objc(L, tbc, "uiviewcontroller");
	return 1;
}

/* A page's back-button display mode applies to the previous page's item,
 * which UIKit renders as this page's back button. */
static char kPageBackButtonModeKey;

@interface LuaNavigationController : UINavigationController <UINavigationControllerDelegate>
@property(nonatomic, readonly) NSInteger depth;
@property(nonatomic, readonly) UIViewController *currentController;
@end
@implementation LuaNavigationController
- (NSInteger)depth { return self.viewControllers.count; }
- (UIViewController *)currentController { return self.topViewController; }
- (void)navigationController:(UINavigationController *)navigation willShowViewController:(UIViewController *)controller animated:(BOOL)animated {
	[navigation setNavigationBarHidden:[objc_getAssociatedObject(controller, &kNavigationBarHiddenKey) boolValue] animated:animated];
	NSNumber *backMode = objc_getAssociatedObject(controller, &kPageBackButtonModeKey);
	NSUInteger index = [navigation.viewControllers indexOfObject:controller];
	if (backMode && index != NSNotFound && index > 0)
		navigation.viewControllers[index - 1].navigationItem.backButtonDisplayMode = backMode.integerValue;
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
	[nav pushViewController:controller animated:!UIAccessibilityIsReduceMotionEnabled()];
	return 0;
}

static UIView *page_toolbar_view(UIView *view, CGFloat maxWidth) {
	CGSize size = measure_size(view, CGSizeMake(maxWidth, CGFLOAT_MAX));
	view.frame = CGRectMake(0, 0, size.width, size.height);
	layout_recursive(view, size.width);
	return view;
}

/* SwiftUI .toolbar placements for a navigation destination. `principal`
 * becomes the title view; leading placements sit beside the back button. */
static int bridge_UIKitNavigation_page_toolbar(lua_State *L) {
	UIViewController *controller = check_view_controller(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	UINavigationItem *navigationItem = controller.navigationItem;
	NSMutableArray<UIBarButtonItem *> *leading = [NSMutableArray array];
	NSMutableArray<UIBarButtonItem *> *trailing = [NSMutableArray array];
	lua_Integer count = luaL_len(L, 2);
	for (lua_Integer i = 1; i <= count; i++) {
		lua_rawgeti(L, 2, i);
		int item = lua_gettop(L);
		lua_getfield(L, item, "placement");
		NSString *placement = lua_isstring(L, -1) ? @(lua_tostring(L, -1)) : @"automatic";
		lua_getfield(L, item, "view");
		UIView *view = lua_isnil(L, -1) ? nil : check_view(L, -1);
		lua_getfield(L, item, "icon");
		NSString *icon = lua_isstring(L, -1) ? @(lua_tostring(L, -1)) : @"";
		lua_getfield(L, item, "label");
		NSString *label = lua_isstring(L, -1) ? @(lua_tostring(L, -1)) : @"";
		lua_getfield(L, item, "action");
		LuaReg *action = lua_isfunction(L, -1) ? lua_reg_create(L, -1, YES) : nil;
		if ([placement isEqualToString:@"principal"]) {
			if (view) navigationItem.titleView = page_toolbar_view(view, kNavigationTitleMaxWidth);
		} else {
			UIBarButtonItem *barItem;
			if (view) {
				barItem = [[UIBarButtonItem alloc] initWithCustomView:page_toolbar_view(view, kNavigationTitleMaxWidth)];
			} else {
				UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration
					configurationWithPointSize:kNavigationSymbolPointSize weight:UIImageSymbolWeightRegular];
				UIImage *image = icon.length ? [[UIImage systemImageNamed:icon] imageByApplyingSymbolConfiguration:symbol] : nil;
				barItem = image
					? [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain
						target:[LuaButtonTarget shared] action:@selector(onAction:)]
					: [[UIBarButtonItem alloc] initWithTitle:label style:UIBarButtonItemStylePlain
						target:[LuaButtonTarget shared] action:@selector(onAction:)];
				if (action) objc_setAssociatedObject(barItem, &kCallbackKey, action, OBJC_ASSOCIATION_RETAIN);
			}
			barItem.accessibilityLabel = label.length ? label : nil;
			BOOL isLeading = [placement isEqualToString:@"topBarLeading"]
				|| [placement isEqualToString:@"navigation"]
				|| [placement isEqualToString:@"cancellationAction"];
			[isLeading ? leading : trailing addObject:barItem];
		}
		lua_settop(L, item - 1);
	}
	navigationItem.leftItemsSupplementBackButton = YES;
	navigationItem.leftBarButtonItems = leading;
	navigationItem.rightBarButtonItems = trailing;

	if (lua_istable(L, 3)) {
		lua_getfield(L, 3, "titleDisplayMode");
		const char *titleMode = lua_tostring(L, -1);
		if (titleMode) {
			if (strcmp(titleMode, "inline") == 0) navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
			else if (strcmp(titleMode, "large") == 0) navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
			else if (strcmp(titleMode, "automatic") == 0) navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAutomatic;
			else return luaL_error(L, "titleDisplayMode must be 'automatic', 'inline', or 'large'");
		}
		lua_getfield(L, 3, "backButtonDisplayMode");
		const char *backMode = lua_tostring(L, -1);
		if (backMode) {
			UINavigationItemBackButtonDisplayMode mode;
			if (strcmp(backMode, "minimal") == 0) mode = UINavigationItemBackButtonDisplayModeMinimal;
			else if (strcmp(backMode, "generic") == 0) mode = UINavigationItemBackButtonDisplayModeGeneric;
			else if (strcmp(backMode, "default") == 0) mode = UINavigationItemBackButtonDisplayModeDefault;
			else return luaL_error(L, "backButtonDisplayMode must be 'default', 'generic', or 'minimal'");
			objc_setAssociatedObject(controller, &kPageBackButtonModeKey, @(mode), OBJC_ASSOCIATION_RETAIN);
		}
		lua_pop(L, 2);
	}
	return 0;
}

static int bridge_UIKitNavigation_pop(lua_State *L) {
	UINavigationController *nav = (UINavigationController *)check_objc(L, 1);
	[nav popViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled()];
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
	LuaReg *callback = lua_reg_opt(L, 2);

	LuaTabBarControllerDelegate *existing = objc_getAssociatedObject(
		tbc, &kTabBarDelegateKey);
	if (existing) {
		tbc.delegate = nil;
		objc_setAssociatedObject(tbc, &kTabBarDelegateKey, nil,
			OBJC_ASSOCIATION_RETAIN);
	}

	if (callback) {
		LuaTabBarControllerDelegate *delegate =
			[[LuaTabBarControllerDelegate alloc] init];
		delegate.selection = callback;
		tbc.delegate = delegate;
		objc_setAssociatedObject(tbc, &kTabBarDelegateKey,
			delegate, OBJC_ASSOCIATION_RETAIN);
	}
	return 0;
}
