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

@interface LuaNavigationView : NSView
@property(nonatomic, strong) LuaPageController *pageController;
@property(nonatomic, readonly) NSInteger depth;
@property(nonatomic, readonly) NSViewController *currentController;
@end
@implementation LuaNavigationView
- (NSInteger)depth { return self.pageController.selectedIndex + 1; }
- (NSViewController *)currentController { return self.pageController.selectedViewController; }
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
	push_objc(L, controller, "nsobject");
	return 1;
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
	page.title = [NSString stringWithUTF8String:luaL_optstring(L, 3, "")];
	LuaPageController *controller = host.pageController;
	NSMutableArray *pages = [[controller.arrangedObjects subarrayWithRange:NSMakeRange(0, controller.selectedIndex + 1)] mutableCopy];
	[pages addObject:page];
	controller.arrangedObjects = pages;
	controller.selectedIndex = pages.count - 1;
	host.needsLayout = YES;
	[host layoutSubtreeIfNeeded];
	return 0;
}

static int bridge_navigation_pop(lua_State *L) {
	LuaNavigationView *host = (LuaNavigationView *)check_view(L, 1);
	LuaPageController *controller = host.pageController;
	if (controller.selectedIndex == 0) return 0;
	controller.selectedIndex--;
	controller.arrangedObjects = [controller.arrangedObjects subarrayWithRange:NSMakeRange(0, controller.selectedIndex + 1)];
	host.needsLayout = YES;
	[host layoutSubtreeIfNeeded];
	return 0;
}
