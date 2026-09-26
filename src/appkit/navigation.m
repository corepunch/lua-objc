#pragma mark - Native page navigation

/* NSPageController's delegate lifecycle and view-controller ownership cannot
 * be expressed through KVC. Native pages retain their own Lua view trees. */
@interface LuaPageController : NSPageController <NSPageControllerDelegate>
@end
@implementation LuaPageController
- (NSPageControllerObjectIdentifier)pageController:(NSPageController *)controller identifierForObject:(id)object {
	return [NSString stringWithFormat:@"%p", object];
}
- (NSViewController *)pageController:(NSPageController *)controller viewControllerForIdentifier:(NSPageControllerObjectIdentifier)identifier {
	for (NSViewController *page in controller.arrangedObjects)
		if ([[self pageController:controller identifierForObject:page] isEqual:identifier]) return page;
	return nil;
}
- (void)pageControllerDidEndLiveTransition:(NSPageController *)controller {
	[controller completeTransition];
}
@end

/* A pushed page: its content, the toolbar items it declares, and the
 * callback run when it leaves the stack (UIKit's viewDidDisappear twin). */
static char kPageToolbarItemsKey;
static char kPageDisappearKey;

static void page_did_disappear(NSViewController *page) {
	LuaReg *callback = objc_getAssociatedObject(page, &kPageDisappearKey);
	objc_setAssociatedObject(page, &kPageDisappearKey, nil, OBJC_ASSOCIATION_RETAIN);
	if (!callback) return;
	lua_State *L = lua_reg_live_state(callback);
	if (L && lua_reg_push(callback)) lua_objc_pcall(L, 0, 0, "page disappear");
	[callback dispose];
}

@interface LuaNavigationView : NSView
@property(nonatomic, strong) LuaPageController *pageController;
@property(nonatomic, strong) LuaReg *backCallback;
@property(nonatomic, readonly) NSInteger depth;
@property(nonatomic, readonly) NSViewController *currentController;
- (void)updateWindowToolbar;
@end
@implementation LuaNavigationView
- (NSInteger)depth { return self.pageController.selectedIndex + 1; }
- (NSViewController *)currentController { return self.pageController.selectedViewController; }
- (void)dealloc { [_backCallback dispose]; }
- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[self updateWindowToolbar];
}
- (void)updateWindowToolbar {
	NSWindow *window = self.window;
	if (!window) return;
	NSMutableArray *items = [NSMutableArray array];
	if (self.depth > 1) {
		[items addObject:@{
			@"id": @"lua-objc.navigation.back", @"label": @"Back",
			@"icon": @"chevron.backward", @"navigational": @YES,
			@"target": self, @"selector": NSStringFromSelector(@selector(navigateBack:)),
		}];
	}
	NSArray *pageItems = objc_getAssociatedObject(self.currentController, &kPageToolbarItemsKey);
	if (pageItems) [items addObjectsFromArray:pageItems];
	window_set_page_toolbar_items(window, items);
}
/* The toolbar back item goes through the stack's Lua pop, so per-screen
 * scopes close exactly as they do for a programmatic pop. */
- (void)navigateBack:(id)sender {
	lua_State *L = lua_reg_live_state(self.backCallback);
	if (L && lua_reg_push(self.backCallback)) {
		lua_objc_pcall(L, 0, 0, "navigation back");
		return;
	}
	[self popPage];
}
- (void)popPage {
	LuaPageController *controller = self.pageController;
	if (controller.selectedIndex == 0) return;
	NSViewController *popped = controller.selectedViewController;
	controller.selectedIndex--;
	controller.arrangedObjects = [controller.arrangedObjects subarrayWithRange:NSMakeRange(0, controller.selectedIndex + 1)];
	self.needsLayout = YES;
	[self layoutSubtreeIfNeeded];
	[self updateWindowToolbar];
	page_did_disappear(popped);
}
- (void)layout {
	[super layout];
	self.pageController.view.frame = self.bounds;
	[self.pageController.view layoutSubtreeIfNeeded];
	[self.pageController viewDidLayout];
	NSView *content = self.pageController.selectedViewController.view;
	if (content) layout_recursive(content, content.bounds.size.width);
}
@end

static int bridge_hosting_controller(lua_State *L) {
	NSViewController *controller = [[NSViewController alloc] init];
	controller.view = check_view(L, 1);
	controller.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	LuaReg *disappear = lua_reg_opt(L, 2);
	if (disappear) objc_setAssociatedObject(controller, &kPageDisappearKey, disappear, OBJC_ASSOCIATION_RETAIN);
	if (lua_istable(L, 3))
		objc_setAssociatedObject(controller, &kPageToolbarItemsKey,
			toolbar_items_from_lua(L, 3), OBJC_ASSOCIATION_RETAIN);
	push_objc(L, controller, "nsobject");
	return 1;
}

static int bridge_navigation_on_back(lua_State *L) {
	LuaNavigationView *host = (LuaNavigationView *)check_view(L, 1);
	[host.backCallback dispose];
	host.backCallback = lua_reg_opt(L, 2);
	return 0;
}

static int bridge_navigation_stack(lua_State *L) {
	NSViewController *root = lua_objc_check_object(L, 1, NSViewController.class, "HostingController");
	LuaPageController *controller = [[LuaPageController alloc] init];
	controller.view = [[NSView alloc] initWithFrame:NSZeroRect];
	controller.delegate = controller;
	controller.transitionStyle = NSPageControllerTransitionStyleStackHistory;
	controller.arrangedObjects = @[root];
	controller.selectedIndex = 0;
	LuaNavigationView *host = [[LuaNavigationView alloc] initWithFrame:NSZeroRect];
	host.pageController = controller;
	[host addSubview:controller.view];
	controller.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	objc_setAssociatedObject(host, &kKeys[kNavigationControllerKey], controller, OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(host, &kKeys[kFlexibleKey], @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, host, "nsview");
	return 1;
}

static int bridge_navigation_push(lua_State *L) {
	LuaNavigationView *host = (LuaNavigationView *)check_view(L, 1);
	NSViewController *page = lua_objc_check_object(L, 2, NSViewController.class, "HostingController");
	const char *title = luaL_optstring(L, 3, "");
	if (title[0]) page.title = @(title);
	LuaPageController *controller = host.pageController;
	NSMutableArray *pages = [[controller.arrangedObjects subarrayWithRange:NSMakeRange(0, controller.selectedIndex + 1)] mutableCopy];
	[pages addObject:page];
	controller.arrangedObjects = pages;
	controller.selectedIndex = pages.count - 1;
	host.needsLayout = YES;
	[host layoutSubtreeIfNeeded];
	[host updateWindowToolbar];
	return 0;
}

static int bridge_navigation_pop(lua_State *L) {
	[(LuaNavigationView *)check_view(L, 1) popPage];
	return 0;
}
