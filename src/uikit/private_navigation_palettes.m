/* Experimental navigation palettes. Keep every private runtime lookup here. */
#import <objc/message.h>

static BOOL private_palette_runtime_supported(void) {
	NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
	/* Only the simulator version exercised by this experiment is enabled. */
	return version.majorVersion == 26 && version.minorVersion == 5;
}

static BOOL install_private_palette(UINavigationItem *item, UIView *content, BOOL top) {
	if (!private_palette_runtime_supported()) return NO;
	Class paletteClass = NSClassFromString(@"_UINavigationBarPalette");
	SEL initializer = NSSelectorFromString(@"initWithContentView:");
	SEL setter = NSSelectorFromString(top ? @"_setTopPalette:" : @"_setBottomPalette:");
	if (!paletteClass || ![paletteClass instancesRespondToSelector:initializer]
		|| ![item respondsToSelector:setter]) return NO;
	id palette = ((id (*)(id, SEL, id))objc_msgSend)([paletteClass alloc], initializer, content);
	if (!palette) return NO;
	((void (*)(id, SEL, id))objc_msgSend)(item, setter, palette);
	return YES;
}

static int bridge_UIKitNavigation_palette(lua_State *L) {
	UINavigationController *navigation = (UINavigationController *)check_objc(L, 1);
	UIView *content = check_view(L, 2);
	BOOL top = strcmp(luaL_checkstring(L, 3), "top") == 0;
	BOOL enabled = lua_toboolean(L, 4);
	UIViewController *controller = navigation.topViewController;
	if (!controller) return luaL_error(L, "navigation palette requires a root controller");
	CGSize size = measure_size(content, CGSizeMake(navigation.view.bounds.size.width, CGFLOAT_MAX));
	if (fills_axis(content, YES)) size.width = MAX(size.width, navigation.view.bounds.size.width);
	content.frame = CGRectMake(0, 0, size.width, size.height);
	layout_recursive(content, size.width);
	BOOL installed = enabled && install_private_palette(controller.navigationItem, content, top);
	if (enabled) NSLog(@"lua-objc private navigation %@ palette: %@ (%@)",
		top ? @"top" : @"bottom", installed ? @"installed" : @"public fallback",
		NSStringFromCGSize(size));
	if (!installed) {
		if (top) {
			controller.navigationItem.titleView = content;
		} else {
			controller.toolbarItems = @[[[UIBarButtonItem alloc] initWithCustomView:content]];
			[navigation setToolbarHidden:NO animated:NO];
		}
	}
	lua_pushboolean(L, installed);
	return 1;
}
