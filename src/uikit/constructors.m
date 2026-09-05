/* Native constructors exported by the UIKit module. */

static int bridge_UIKitControls_vstack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_hstack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_zstack(lua_State *L) {
	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"zstack", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

@interface LuaUIKitScrollView : UIScrollView
@property (nonatomic, strong) UIView *luaContent;
@end

@implementation LuaUIKitScrollView
- (void)layoutSubviews {
	[super layoutSubviews];
	if (!self.luaContent) return;
	CGFloat width = MAX(self.bounds.size.width, self.luaContent.frame.size.width);
	/* A scroll view's content is measured independently of the viewport. If
	 * height is left at zero, a flexible VStack otherwise collapses before its
	 * descendants can be laid out, producing clipped images and missing rows. */
	CGFloat height = self.luaContent.frame.size.height;
	height = MAX(height, natural_height(self.luaContent));
	self.luaContent.frame = CGRectMake(0, 0, width, height);
	layout_recursive(self.luaContent, width);
	self.contentSize = CGSizeMake(MAX(width, self.luaContent.frame.size.width),
		MAX(self.bounds.size.height, self.luaContent.frame.size.height));
}
@end

static int bridge_UIKitControls_scrollView(lua_State *L) {
	UIView *content = check_view(L, 1);
	CGFloat contentWidth = (CGFloat)luaL_optnumber(L, 2, 0);
	CGFloat contentHeight = (CGFloat)luaL_optnumber(L, 3, 0);
	BOOL horizontal = lua_toboolean(L, 4);
	BOOL vertical = lua_toboolean(L, 5);
	LuaUIKitScrollView *scroll = [[LuaUIKitScrollView alloc] initWithFrame:CGRectZero];
	scroll.luaContent = content;
	scroll.alwaysBounceHorizontal = horizontal;
	scroll.alwaysBounceVertical = vertical;
	scroll.showsHorizontalScrollIndicator = horizontal;
	scroll.showsVerticalScrollIndicator = vertical;
	[scroll addSubview:content];
	CGRect frame = content.frame;
	if (contentWidth > 0) frame.size.width = contentWidth;
	if (contentHeight > 0) frame.size.height = contentHeight;
	content.frame = frame;
	objc_setAssociatedObject(scroll, &kScrollContentKey, content,
		OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(scroll, &kFlexibleKey, @YES,
		OBJC_ASSOCIATION_RETAIN);
	push_objc(L, scroll, "uiview");
	return 1;
}

static int bridge_UIKitControls_hsplit(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"hsplit", OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_spacer(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
	objc_setAssociatedObject(obj, &kFlexibleKey, @YES, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_textField(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	UITextField *obj = [[UITextField alloc] initWithFrame:CGRectZero];
	obj.text = [NSString stringWithUTF8String:text];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_label(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	UILabel *obj = [[UILabel alloc] initWithFrame:CGRectZero];
	obj.text = [NSString stringWithUTF8String:text];
	/* SwiftUI Text is single-line unless the caller requests a line limit. */
	obj.numberOfLines = 1;
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_separator(lua_State *L) {
	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kFixedHeightKey, @1,
		OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, &kFillWidthKey, @YES,
		OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_progressIndicator(lua_State *L) {
	UIActivityIndicatorView *obj =
		[[UIActivityIndicatorView alloc] initWithFrame:CGRectZero];
	[obj startAnimating];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_pageControl(lua_State *L) {
	NSInteger pages = (NSInteger)luaL_optinteger(L, 1, 0);
	UIPageControl *control = [[UIPageControl alloc] initWithFrame:CGRectZero];
	control.numberOfPages = MAX(0, pages);
	control.currentPage = (NSInteger)luaL_optinteger(L, 2, 0);
	[control sizeToFit];
	push_objc(L, control, "uiview");
	return 1;
}

static int bridge_UIKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	BOOL has_callback = !lua_isnoneornil(L, 2);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIButton *obj = [UIButton buttonWithType:UIButtonTypeSystem];
	[obj setTitle:[NSString stringWithUTF8String:title] forState:UIControlStateNormal];
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:) forControlEvents:UIControlEventTouchUpInside];
	}
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	BOOL has_callback = !lua_isnoneornil(L, 3);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UISwitch *obj = [[UISwitch alloc] initWithFrame:CGRectZero];
	obj.on = is_on;
	obj.accessibilityLabel = [NSString stringWithUTF8String:label];
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:) forControlEvents:UIControlEventValueChanged];
	}
	push_objc(L, obj, "uiview");
	return 1;
}
