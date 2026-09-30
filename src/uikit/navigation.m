#pragma mark - UITabBarController bridge

@interface LuaTabBarControllerDelegate : NSObject <UITabBarControllerDelegate>
@property (nonatomic, strong) LuaReg *selection;
@end

@implementation LuaTabBarControllerDelegate
- (void)dealloc {
	[_selection dispose];
}

- (void)tabBarController:(UITabBarController *)tabBarController
		didSelectTab:(UITab *)selectedTab previousTab:(UITab *)previousTab {
	lua_State *L = lua_reg_live_state(_selection);
	if (!L) return;
	int top = lua_gettop(L);
	if (!lua_reg_push(_selection)) return;
	push_objc(L, tabBarController, "uiviewcontroller");
	lua_pushinteger(L, [tabBarController.tabs indexOfObject:selectedTab]);
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
		fprintf(stderr, "tab selection error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	lua_settop(L, top);
}
@end

static char kTabBarDelegateKey;

/* SwiftUI `tabViewBottomAccessory`: iOS 26 floats the accessory in its own
 * Liquid Glass capsule above the tab bar, and moves it inline beside the
 * minimized bar while content scrolls. UIKit sizes the capsule, so the host
 * lays out the Lua content whenever the system changes that size. */
@interface LuaTabAccessoryHost : UIView
@property(nonatomic, strong) UIView *luaContent;
@end
@implementation LuaTabAccessoryHost
- (void)layoutSubviews {
	[super layoutSubviews];
	self.luaContent.frame = self.bounds;
	layout_recursive(self.luaContent, self.bounds.size.width);
}
@end

/* `accessoryHidden` is SwiftUI's `tabViewBottomAccessory(isEnabled:)`: the
 * accessory keeps its content and state while it is removed from the bar. */
@interface LuaTabBarController : UITabBarController
@property(nonatomic, strong) UITabAccessory *luaAccessory;
@property(nonatomic) BOOL accessoryHidden;
@end
@implementation LuaTabBarController
- (void)setAccessoryHidden:(BOOL)hidden {
	_accessoryHidden = hidden;
	[self setBottomAccessory:hidden ? nil : self.luaAccessory
		animated:self.viewIfLoaded.window != nil && !UIAccessibilityIsReduceMotionEnabled()];
}
@end

static int bridge_tabview_accessory(lua_State *L) {
	LuaTabBarController *tbc = lua_objc_check_object(L, 1, [LuaTabBarController class], "TabView");
	UIView *content = check_view(L, 2);
	LuaTabAccessoryHost *host = [[LuaTabAccessoryHost alloc] initWithFrame:CGRectZero];
	host.luaContent = content;
	[host addSubview:content];
	tbc.luaAccessory = [[UITabAccessory alloc] initWithContentView:host];
	tbc.accessoryHidden = lua_toboolean(L, 3);
	return 0;
}

static int bridge_tabview(lua_State *L) {
	LuaTabBarController *tbc = [[LuaTabBarController alloc] init];
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
/* The page decides the status bar: a page forced dark (a reader's Night
 * theme) needs light status text whatever the system appearance is. */
- (UIViewController *)childViewControllerForStatusBarStyle { return self.topViewController; }
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

/* The bar above the keyboard for a page's `keyboard` toolbar items, set as
 * the editing input's inputAccessoryView. Items keep their own look (glass
 * buttons float over the keyboard as the system's own keyboard toolbar does)
 * and share one row: fixed-width items take their fitting width and items
 * that want more (maxWidth="infinity") split what remains. While every item
 * is hidden the input has no accessory at all. Showing or hiding the bar goes
 * through -reloadInputViews on the editing input, the documented way to
 * change input views; resizing a live accessory to zero instead leaves the
 * keyboard layout guide short by the old bar's height. */
@interface LuaKeyboardToolbar : UIView
@property(nonatomic, copy) NSArray<UIView *> *items;
/* The input that last asked for the bar; reloaded when visibility flips. */
@property(nonatomic, weak) UIResponder *input;
@property(nonatomic, readonly) BOOL hasVisibleItems;
@end
@implementation LuaKeyboardToolbar {
	BOOL _shown;
}
static void *kKeyboardToolbarHiddenContext = &kKeyboardToolbarHiddenContext;
- (instancetype)initWithItems:(NSArray<UIView *> *)items {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;
	self.autoresizingMask = UIViewAutoresizingFlexibleHeight;
	_items = [items copy];
	for (UIView *item in _items) {
		[self addSubview:item];
		[item addObserver:self forKeyPath:@"hidden" options:0 context:kKeyboardToolbarHiddenContext];
	}
	_shown = self.hasVisibleItems;
	return self;
}
- (void)dealloc {
	for (UIView *item in _items) [item removeObserver:self forKeyPath:@"hidden" context:kKeyboardToolbarHiddenContext];
}
- (BOOL)hasVisibleItems {
	for (UIView *item in _items) if (!item.hidden) return YES;
	return NO;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
		change:(NSDictionary *)change context:(void *)context {
	if (context != kKeyboardToolbarHiddenContext) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	BOOL shown = self.hasVisibleItems;
	if (shown != _shown) {
		_shown = shown;
		if (_input.isFirstResponder) [_input reloadInputViews];
	}
	[self invalidateIntrinsicContentSize];
	[self setNeedsLayout];
}
- (CGFloat)itemWidth {
	CGFloat width = self.bounds.size.width ?: self.window.bounds.size.width ?: UIScreen.mainScreen.bounds.size.width;
	return MAX(0, width - 2 * kKeyboardToolbarHorizontalInset);
}
- (CGSize)intrinsicContentSize {
	CGFloat height = 0;
	for (UIView *item in _items)
		height = MAX(height, measure_size(item, CGSizeMake([self itemWidth], CGFLOAT_MAX)).height);
	return CGSizeMake(UIViewNoIntrinsicMetric, height + 2 * kKeyboardToolbarVerticalInset);
}
- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat available = [self itemWidth];
	NSMutableArray<UIView *> *visible = [NSMutableArray array];
	for (UIView *item in _items) if (!item.hidden) [visible addObject:item];
	if (visible.count == 0) return;
	available -= (visible.count - 1) * kKeyboardToolbarSpacing;
	CGFloat fixed = 0;
	NSUInteger flexible = 0;
	CGSize sizes[visible.count];
	for (NSUInteger index = 0; index < visible.count; index++) {
		sizes[index] = measure_size(visible[index], CGSizeMake(available, CGFLOAT_MAX));
		if (sizes[index].width >= available) flexible++;
		else fixed += sizes[index].width;
	}
	CGFloat share = flexible ? MAX(0, available - fixed) / flexible : 0;
	CGFloat x = kKeyboardToolbarHorizontalInset;
	for (NSUInteger index = 0; index < visible.count; index++) {
		CGFloat width = sizes[index].width >= available ? share : sizes[index].width;
		CGFloat y = floor((self.bounds.size.height - sizes[index].height) / 2);
		visible[index].frame = CGRectMake(x, y, width, sizes[index].height);
		layout_recursive(visible[index], width);
		x += width + kKeyboardToolbarSpacing;
	}
}
@end

/* The bar for an input that is about to edit, or nil while it shows nothing. */
static UIView *keyboard_toolbar_for_input(LuaKeyboardToolbar *toolbar, UIResponder *input) {
	toolbar.input = input;
	return toolbar.hasVisibleItems ? toolbar : nil;
}

/* SwiftUI .toolbar placements for a navigation destination. `principal`
 * becomes the title view; leading placements sit beside the back button;
 * `keyboard` items ride above the keyboard (LuaKeyboardToolbar). */
static int bridge_UIKitNavigation_page_toolbar(lua_State *L) {
	UIViewController *controller = check_view_controller(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);
	UINavigationItem *navigationItem = controller.navigationItem;
	NSMutableArray<UIBarButtonItem *> *leading = [NSMutableArray array];
	NSMutableArray<UIBarButtonItem *> *trailing = [NSMutableArray array];
	NSMutableArray<UIView *> *keyboard = [NSMutableArray array];
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
		if ([placement isEqualToString:@"keyboard"]) {
			if (!view) return luaL_error(L, "a keyboard ToolbarItem requires one view child");
			[keyboard addObject:view];
		} else if ([placement isEqualToString:@"principal"]) {
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
	objc_setAssociatedObject(controller, &kKeyboardToolbarKey,
		keyboard.count ? [[LuaKeyboardToolbar alloc] initWithItems:keyboard] : nil, OBJC_ASSOCIATION_RETAIN);

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

/* Tabs use the iOS 18+ UITab API so a `search` role becomes a UISearchTab:
 * iOS 26 separates it from the other tabs as its own Liquid Glass button,
 * and keeps it beside the minimized bar while content scrolls. */
static int bridge_UIKitTabView_addTab(lua_State *L) {
	UITabBarController *tbc = lua_objc_check_object(L, 1, [UITabBarController class], "TabView");
	UIViewController *vc = check_view_controller(L, 2);
	NSString *title = @(luaL_optstring(L, 3, ""));
	NSString *systemImage = @(luaL_optstring(L, 4, ""));
	BOOL search = strcmp(luaL_optstring(L, 5, ""), "search") == 0;
	UIViewController *(^provider)(UITab *) = ^UIViewController *(UITab *tab) { return vc; };
	UITab *tab = search
		? [[UISearchTab alloc] initWithViewControllerProvider:provider]
		: [[UITab alloc] initWithTitle:title
			image:systemImage.length ? [UIImage systemImageNamed:systemImage] : nil
			identifier:[NSString stringWithFormat:@"tab.%lu", (unsigned long)tbc.tabs.count]
			viewControllerProvider:provider];
	if (search && title.length) tab.title = title;
	tbc.tabs = [(tbc.tabs ?: @[]) arrayByAddingObject:tab];
	push_objc(L, vc, "uiviewcontroller");
	return 1;
}

static int bridge_UIKitTabView_selectTab(lua_State *L) {
	UITabBarController *tbc = lua_objc_check_object(L, 1, [UITabBarController class], "TabView");
	NSInteger index = (NSInteger)luaL_checkinteger(L, 2);
	if (index >= 0 && index < (NSInteger)tbc.tabs.count) tbc.selectedTab = tbc.tabs[index];
	return 0;
}

static int bridge_UIKitTabView_tabCount(lua_State *L) {
	UITabBarController *tbc = lua_objc_check_object(L, 1, [UITabBarController class], "TabView");
	lua_pushinteger(L, (lua_Integer)tbc.tabs.count);
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
