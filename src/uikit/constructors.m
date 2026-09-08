/* Native constructors exported by the UIKit module. */

@interface LuaLinkTarget : NSObject
@property (nonatomic, strong) NSURL *url;
@end

@implementation LuaLinkTarget
- (void)onAction:(id)sender {
	if (self.url) [[UIApplication sharedApplication] openURL:self.url
		options:@{} completionHandler:nil];
}
@end

@interface LuaPickerDataSource : NSObject <UIPickerViewDataSource, UIPickerViewDelegate>
@property (nonatomic, copy) NSArray<NSString *> *options;
@end

@implementation LuaPickerDataSource
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView { return 1; }
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
	return self.options.count;
}
- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row
	forComponent:(NSInteger)component {
	return self.options[(NSUInteger)row];
}
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row
	inComponent:(NSInteger)component {
	id refObj = objc_getAssociatedObject(pickerView, &kCallbackKey);
	if (!refObj || !gL) return;
	lua_rawgeti(gL, LUA_REGISTRYINDEX, [refObj intValue]);
	push_objc(gL, pickerView, "uiview");
	lua_objc_pcall(gL, 1, 0, "picker");
}
@end

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
	self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	self.contentInset = UIEdgeInsetsZero;
	self.scrollIndicatorInsets = UIEdgeInsetsZero;
	if (self.contentOffset.y != 0)
		self.contentOffset = CGPointMake(self.contentOffset.x, 0);
	CGFloat width = MAX(self.bounds.size.width, self.luaContent.frame.size.width);
	/* A scroll view's content is measured independently of the viewport. If
	 * height is left at zero, a flexible VStack otherwise collapses before its
	 * descendants can be laid out, producing clipped images and missing rows. */
	CGFloat height = self.luaContent.frame.size.height;
	height = MAX(height, natural_height(self.luaContent));
	self.luaContent.frame = CGRectMake(0, 0, width, height);
	layout_recursive(self.luaContent, width);
	/* Horizontal SwiftUI scroll views pin their row to the top of the
	 * viewport. Keep the row's cards from inheriting a centered/bottom
	 * placement when its measured height is smaller than the viewport. */
	NSString *axis = objc_getAssociatedObject(self.luaContent, &kAxisKey);
	if ([axis isEqualToString:@"hstack"]) {
		for (UIView *child in self.luaContent.subviews) {
			CGRect frame = child.frame;
			child.frame = CGRectMake(frame.origin.x, 0, frame.size.width, frame.size.height);
		}
	}
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
	/* Safe-area placement is owned by LuaHostingController. Automatic UIKit
	 * adjustment would add the same inset again to the root scroll content. */
	scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	scroll.contentInset = UIEdgeInsetsZero;
	scroll.scrollIndicatorInsets = UIEdgeInsetsZero;
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

static int bridge_UIKitControls_searchField(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	const char *placeholder = luaL_optstring(L, 2, "Search");
	UISearchTextField *obj = [[UISearchTextField alloc] initWithFrame:CGRectZero];
	obj.text = [NSString stringWithUTF8String:text];
	obj.placeholder = [NSString stringWithUTF8String:placeholder];
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_textEditor(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	UITextView *obj = [[UITextView alloc] initWithFrame:CGRectZero];
	obj.text = [NSString stringWithUTF8String:text];
	obj.editable = lua_isnoneornil(L, 2) ? YES : lua_toboolean(L, 2);
	obj.selectable = lua_isnoneornil(L, 3) ? YES : lua_toboolean(L, 3);
	if (!lua_isnoneornil(L, 4) && !lua_toboolean(L, 4))
		obj.backgroundColor = UIColor.clearColor;
	obj.scrollEnabled = YES;
	obj.font = [UIFont systemFontOfSize:17.0];
	[obj sizeToFit];
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

static int bridge_UIKitControls_progressView(lua_State *L) {
	CGFloat progress = (CGFloat)luaL_optnumber(L, 1, 0);
	UIProgressView *obj = [[UIProgressView alloc]
		initWithProgressViewStyle:UIProgressViewStyleDefault];
	obj.progress = MIN(MAX(progress, 0.0), 1.0);
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}

@interface LuaPageControlView : UIView
@property(nonatomic, strong) UIPageControl *control;
@end

@implementation LuaPageControlView
- (void)layoutSubviews {
	[super layoutSubviews];
	self.control.frame = self.bounds;
}
@end

static int bridge_UIKitControls_pageControl(lua_State *L) {
	NSInteger pages = (NSInteger)luaL_optinteger(L, 1, 0);
	LuaPageControlView *view = [[LuaPageControlView alloc] initWithFrame:CGRectMake(0, 0, 88, 32)];
	view.backgroundColor = UIColor.clearColor;
	view.control = [[UIPageControl alloc] initWithFrame:view.bounds];
	view.control.numberOfPages = MAX(0, pages);
	view.control.currentPage = (NSInteger)luaL_optinteger(L, 2, 0);
	view.control.pageIndicatorTintColor = [UIColor colorWithWhite:0.8 alpha:0.8];
	view.control.currentPageIndicatorTintColor = UIColor.whiteColor;
	[view addSubview:view.control];
	push_objc(L, view, "uiview");
	return 1;
}

@interface LuaGradientView : UIView
@property(nonatomic, strong) CAGradientLayer *gradient;
@end

@implementation LuaGradientView
- (void)layoutSubviews {
	[super layoutSubviews];
	self.gradient.frame = self.bounds;
}
@end

static int bridge_UIKitControls_linearGradient(lua_State *L) {
	CGFloat topAlpha = (CGFloat)luaL_optnumber(L, 1, 0);
	CGFloat middleAlpha = (CGFloat)luaL_optnumber(L, 2, 0.5);
	CGFloat middleLocation = (CGFloat)luaL_optnumber(L, 3, 0.6);
	CGFloat bottomAlpha = (CGFloat)luaL_optnumber(L, 4, 0.82);
	LuaGradientView *view = [[LuaGradientView alloc] initWithFrame:CGRectZero];
	CAGradientLayer *gradient = [CAGradientLayer layer];
	gradient.colors = @[(id)[UIColor colorWithWhite:0 alpha:topAlpha].CGColor,
		(id)[UIColor colorWithWhite:0 alpha:topAlpha].CGColor,
		(id)[UIColor colorWithWhite:0 alpha:middleAlpha].CGColor,
		(id)[UIColor colorWithWhite:0 alpha:bottomAlpha].CGColor];
	gradient.locations = @[@0.0, @0.3, @(middleLocation), @1.0];
	gradient.startPoint = CGPointMake(0.5, 0);
	gradient.endPoint = CGPointMake(0.5, 1);
	view.gradient = gradient;
	[view.layer addSublayer:gradient];
	view.userInteractionEnabled = NO;
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_UIKitControls_button(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	BOOL has_callback = !lua_isnoneornil(L, 2);
	const char *style = luaL_optstring(L, 3, "default");
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 2, LUA_TFUNCTION);
		lua_pushvalue(L, 2);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIButton *obj = [UIButton buttonWithType:UIButtonTypeSystem];
	NSString *buttonTitle = [NSString stringWithUTF8String:title];
	if (strcmp(style, "bordered") == 0) {
		UIButtonConfiguration *configuration =
			[UIButtonConfiguration borderedButtonConfiguration];
		configuration.title = buttonTitle;
		obj.configuration = configuration;
	} else if (strcmp(style, "borderedProminent") == 0) {
		UIButtonConfiguration *configuration =
			[UIButtonConfiguration filledButtonConfiguration];
		configuration.title = buttonTitle;
		obj.configuration = configuration;
	} else if (strcmp(style, "plain") == 0 || strcmp(style, "link") == 0) {
		UIButtonConfiguration *configuration =
			[UIButtonConfiguration plainButtonConfiguration];
		configuration.title = buttonTitle;
		obj.configuration = configuration;
		[obj setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
		obj.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	} else {
		[obj setTitle:buttonTitle forState:UIControlStateNormal];
	}
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref), OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:) forControlEvents:UIControlEventTouchUpInside];
	}
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_link(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	const char *urlString = luaL_checkstring(L, 2);
	NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:urlString]];
	if (!url) return luaL_error(L, "Link URL is invalid");

	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *configuration =
		[UIButtonConfiguration plainButtonConfiguration];
	configuration.title = [NSString stringWithUTF8String:title];
	button.configuration = configuration;
	button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	LuaLinkTarget *target = [[LuaLinkTarget alloc] init];
	target.url = url;
	[button addTarget:target action:@selector(onAction:)
		forControlEvents:UIControlEventTouchUpInside];
	objc_setAssociatedObject(button, &kCallbackKey, target,
		OBJC_ASSOCIATION_RETAIN);
	[button sizeToFit];
	push_objc(L, button, "uiview");
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

static int bridge_UIKitControls_slider(lua_State *L) {
	CGFloat minimum = luaL_optnumber(L, 1, 0);
	CGFloat maximum = luaL_optnumber(L, 2, 1);
	CGFloat value = luaL_optnumber(L, 3, minimum);
	BOOL has_callback = !lua_isnoneornil(L, 4);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 4, LUA_TFUNCTION);
		lua_pushvalue(L, 4);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UISlider *obj = [[UISlider alloc] initWithFrame:CGRectZero];
	obj.minimumValue = minimum;
	obj.maximumValue = MAX(minimum, maximum);
	obj.value = MIN(MAX(value, minimum), obj.maximumValue);
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref),
			OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared]
			action:@selector(onAction:)
			forControlEvents:UIControlEventValueChanged];
	}
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_stepper(lua_State *L) {
	CGFloat minimum = luaL_optnumber(L, 1, 0);
	CGFloat maximum = luaL_optnumber(L, 2, 100);
	CGFloat value = luaL_optnumber(L, 3, minimum);
	CGFloat step = luaL_optnumber(L, 4, 1);
	BOOL has_callback = !lua_isnoneornil(L, 5);
	int callback_ref = LUA_NOREF;
	if (has_callback) {
		luaL_checktype(L, 5, LUA_TFUNCTION);
		lua_pushvalue(L, 5);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIStepper *obj = [[UIStepper alloc] initWithFrame:CGRectZero];
	obj.minimumValue = minimum;
	obj.maximumValue = MAX(minimum, maximum);
	obj.stepValue = MAX(0, step);
	obj.value = MIN(MAX(value, minimum), obj.maximumValue);
	[obj sizeToFit];
	if (has_callback) {
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref),
			OBJC_ASSOCIATION_RETAIN);
		[obj addTarget:[LuaButtonTarget shared]
			action:@selector(onAction:)
			forControlEvents:UIControlEventValueChanged];
	}
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_picker(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	NSInteger count = (NSInteger)luaL_len(L, 1);
	if (count < 1) return luaL_error(L, "Picker options must not be empty");
	NSMutableArray<NSString *> *options = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
	for (NSInteger i = 1; i <= count; i++) {
		lua_rawgeti(L, 1, i);
		const char *value = luaL_checkstring(L, -1);
		[options addObject:[NSString stringWithUTF8String:value]];
		lua_pop(L, 1);
	}
	NSInteger selected = luaL_optinteger(L, 2, 0);
	selected = MIN(MAX(selected, 0), count - 1);
	int callback_ref = LUA_NOREF;
	if (!lua_isnoneornil(L, 3)) {
		luaL_checktype(L, 3, LUA_TFUNCTION);
		lua_pushvalue(L, 3);
		callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}

	UIPickerView *obj = [[UIPickerView alloc] initWithFrame:CGRectZero];
	LuaPickerDataSource *source = [[LuaPickerDataSource alloc] init];
	source.options = options;
	obj.dataSource = source;
	obj.delegate = source;
	[obj selectRow:(NSUInteger)selected inComponent:0 animated:NO];
	objc_setAssociatedObject(obj, &kTableSourceKey, source, OBJC_ASSOCIATION_RETAIN);
	if (callback_ref != LUA_NOREF)
		objc_setAssociatedObject(obj, &kCallbackKey, @(callback_ref), OBJC_ASSOCIATION_RETAIN);
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}
