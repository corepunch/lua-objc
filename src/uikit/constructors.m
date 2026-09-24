/* Native constructors exported by the UIKit module. */
#import <WebKit/WebKit.h>

static int bridge_UIKit_hapticsAvailable(lua_State *L) {
	lua_pushboolean(L, UIImpactFeedbackGenerator.class != nil);
	return 1;
}
static int bridge_UIKit_reduceMotionEnabled(lua_State *L) {
	lua_pushboolean(L, UIAccessibilityIsReduceMotionEnabled());
	return 1;
}
static int bridge_UIKit_hapticImpact(lua_State *L) {
	const char *style = luaL_optstring(L, 1, "medium");
	UIImpactFeedbackStyle value = UIImpactFeedbackStyleMedium;
	if (strcmp(style, "light") == 0) value = UIImpactFeedbackStyleLight;
	else if (strcmp(style, "heavy") == 0) value = UIImpactFeedbackStyleHeavy;
	UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:value];
	[generator prepare]; [generator impactOccurred];
	return 0;
}
static int bridge_UIKit_hapticSelection(lua_State *L) {
	UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
	[generator prepare]; [generator selectionChanged];
	return 0;
}
static int bridge_UIKit_hapticNotification(lua_State *L) {
	const char *kind = luaL_optstring(L, 1, "success");
	UINotificationFeedbackType value = UINotificationFeedbackTypeSuccess;
	if (strcmp(kind, "warning") == 0) value = UINotificationFeedbackTypeWarning;
	else if (strcmp(kind, "error") == 0) value = UINotificationFeedbackTypeError;
	UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
	[generator prepare]; [generator notificationOccurred:value];
	return 0;
}

@interface LuaWebView : WKWebView <WKNavigationDelegate>
@property (nonatomic, strong) LuaReg *stateCallback;
@end

@implementation LuaWebView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self addObserver:self forKeyPath:@"estimatedProgress"
		options:NSKeyValueObservingOptionNew context:NULL];
	return self;
}
- (void)dealloc { [self removeObserver:self forKeyPath:@"estimatedProgress"]; }
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if ([keyPath isEqualToString:@"estimatedProgress"]) { [self publishState]; return; }
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)publishState {
	LuaReg *reg = self.stateCallback;
	if (!reg || !lua_reg_push(reg)) return;
	lua_State *L = reg.owner.L;
	lua_pushliteral(L, "state"); lua_newtable(L);
	lua_pushstring(L, self.URL.absoluteString.UTF8String ?: ""); lua_setfield(L, -2, "url");
	lua_pushstring(L, self.title.UTF8String ?: ""); lua_setfield(L, -2, "title");
	lua_pushnumber(L, self.estimatedProgress); lua_setfield(L, -2, "progress");
	lua_pushboolean(L, self.canGoBack); lua_setfield(L, -2, "canGoBack");
	lua_pushboolean(L, self.canGoForward); lua_setfield(L, -2, "canGoForward");
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
	LuaReg *reg = self.stateCallback;
	if (!reg || !lua_reg_push(reg)) return;
	lua_State *L = reg.owner.L; lua_pushliteral(L, "loading"); lua_pushboolean(L, 1);
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation { [self publishState]; }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	[self publishState];
	LuaReg *reg = self.stateCallback;
	if (!reg || !lua_reg_push(reg)) return;
	lua_State *L = reg.owner.L; lua_pushliteral(L, "loading"); lua_pushboolean(L, 0);
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	LuaReg *reg = self.stateCallback;
	if (!reg || !lua_reg_push(reg)) return;
	lua_State *L = reg.owner.L; lua_pushliteral(L, "error");
	lua_pushstring(L, error.localizedDescription.UTF8String ?: "Web page failed");
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) report_lua_error(L, "WebView state callback");
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self webView:webView didFailNavigation:navigation withError:error];
}
@end

static int bridge_UIKitControls_webView(lua_State *L) {
	const char *url = luaL_checkstring(L, 1); luaL_checktype(L, 2, LUA_TFUNCTION);
	LuaWebView *view = [[LuaWebView alloc] initWithFrame:CGRectZero];
	view.stateCallback = lua_reg_create(L, 2, YES); view.navigationDelegate = view;
	NSURL *URL = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
	if (URL) [view loadRequest:[NSURLRequest requestWithURL:URL]];
	push_objc(L, view, "uiview"); return 1;
}

static int bridge_UIKitControls_webViewAction(lua_State *L) {
	LuaWebView *view = (LuaWebView *)lua_objc_check_object(L, 1, [LuaWebView class], "WebView");
	const char *action = luaL_checkstring(L, 2);
	if (strcmp(action, "back") == 0) [view goBack];
	else if (strcmp(action, "forward") == 0) [view goForward];
	else if (strcmp(action, "reload") == 0) [view reload];
	else if (strcmp(action, "stop") == 0) [view stopLoading];
	else if (strcmp(action, "load") == 0) {
		NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:luaL_checkstring(L, 3)]];
		if (url) [view loadRequest:[NSURLRequest requestWithURL:url]];
	} else if (strcmp(action, "evaluateJavaScript") == 0) {
		LuaReg *callback = lua_isfunction(L, 4) ? lua_reg_create(L, 4, YES) : nil;
		[view evaluateJavaScript:[NSString stringWithUTF8String:luaL_checkstring(L, 3)] completionHandler:^(id result, NSError *error) {
			if (!callback || !lua_reg_push(callback)) return;
			lua_State *state = callback.owner.L;
			if (error) { lua_pushnil(state); lua_pushstring(state, error.localizedDescription.UTF8String ?: "JavaScript failed"); }
			else if ([result isKindOfClass:[NSString class]]) { lua_pushstring(state, [result UTF8String]); lua_pushnil(state); }
			else if ([result isKindOfClass:[NSNumber class]]) { lua_pushnumber(state, [result doubleValue]); lua_pushnil(state); }
			else { lua_pushnil(state); lua_pushnil(state); }
			if (lua_pcall(state, 2, 0, 0) != LUA_OK) report_lua_error(state, "WebView JavaScript callback");
		}];
	} else if (strcmp(action, "find") == 0) {
		NSString *query = [NSString stringWithUTF8String:luaL_checkstring(L, 3)];
		WKFindConfiguration *config = [[WKFindConfiguration alloc] init];
		config.backwards = lua_toboolean(L, 4);
		config.caseSensitive = lua_toboolean(L, 5);
		config.wraps = lua_toboolean(L, 6);
		LuaReg *callback = lua_isfunction(L, 7) ? lua_reg_create(L, 7, YES) : nil;
		[view findString:query withConfiguration:config completionHandler:^(WKFindResult *result) {
			if (!callback || !lua_reg_push(callback)) return;
			lua_State *state = callback.owner.L;
			lua_pushboolean(state, result.matchFound);
			if (lua_pcall(state, 1, 0, 0) != LUA_OK) report_lua_error(state, "WebView find callback");
		}];
	} else if (strcmp(action, "setPageZoom") == 0) {
		CGFloat zoom = (CGFloat)luaL_checknumber(L, 3);
		if (zoom <= 0) return luaL_error(L, "page zoom must be positive");
		view.pageZoom = zoom;
	} else return luaL_error(L, "unknown WebView action: %s", action);
	return 0;
}

@interface LuaMaterialView : UIVisualEffectView
@property (nonatomic, strong) UIView *luaContent;
@property (nonatomic) CGSize minimumContentSize;
@end

@implementation LuaMaterialView
- (void)layoutSubviews {
	[super layoutSubviews];
	self.luaContent.frame = self.contentView.bounds;
	layout_recursive(self.luaContent, self.contentView.bounds.size.width);
}
@end

static int bridge_UIKitControls_materialView(lua_State *L) {
	const char *material = luaL_optstring(L, 1, "regular");
	UIView *content = check_view(L, 2);
	UIBlurEffectStyle style = UIBlurEffectStyleSystemMaterial;
	if (strcmp(material, "thick") == 0)
		style = UIBlurEffectStyleSystemThickMaterial;
	else if (strcmp(material, "thin") == 0)
		style = UIBlurEffectStyleSystemThinMaterial;
	LuaMaterialView *view = [[LuaMaterialView alloc]
		initWithEffect:[UIBlurEffect effectWithStyle:style]];
	view.luaContent = content;
	[view.contentView addSubview:content];
	objc_setAssociatedObject(view, &kVisualEffectContentKey, content,
		OBJC_ASSOCIATION_RETAIN);
	push_objc(L, view, "uiview");
	return 1;
}

@interface LuaGlassEffectView : UIVisualEffectView
@end

@implementation LuaGlassEffectView
- (void)setCornerRadius:(CGFloat)value {
	CGFloat radius = MAX(0, value);
	objc_setAssociatedObject(self, &kCornerRadiusKey, @(radius), OBJC_ASSOCIATION_RETAIN);
	// Glass owns the material's shape. The ordinary UIView cornerRadius alias
	// also masks content, which is a different modifier from glassEffect.
	self.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:
		[UICornerRadius fixedRadius:radius]];
}
@end

static int bridge_UIKitControls_glassEffect(lua_State *L) {
	UIView *content = check_view(L, 1);
	const char *styleName = luaL_optstring(L, 2, "regular");
	CGFloat cornerRadius = luaL_optnumber(L, 3, 0);
	BOOL interactive = lua_toboolean(L, 4);
	UIGlassEffectStyle style;
	if (strcmp(styleName, "regular") == 0) style = UIGlassEffectStyleRegular;
	else if (strcmp(styleName, "clear") == 0) style = UIGlassEffectStyleClear;
	else return luaL_error(L, "glass style must be 'regular' or 'clear'");
	UIGlassEffect *effect = [UIGlassEffect effectWithStyle:style];
	effect.interactive = interactive;
	LuaGlassEffectView *view = [[LuaGlassEffectView alloc] initWithEffect:effect];
	if (lua_isnoneornil(L, 3)) view.cornerConfiguration = UICornerConfiguration.capsuleConfiguration;
	else view.cornerRadius = cornerRadius;
	content.frame = view.contentView.bounds;
	content.autoresizingMask = UIViewAutoresizingFlexibleWidth
		| UIViewAutoresizingFlexibleHeight;
	[view.contentView addSubview:content];
	objc_setAssociatedObject(view, &kVisualEffectContentKey, content,
		OBJC_ASSOCIATION_RETAIN);
	[view sizeToFit];
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_UIKitControls_glassEffectContainer(lua_State *L) {
	UIView *content = check_view(L, 1);
	CGFloat spacing = (CGFloat)luaL_optnumber(L, 2, 0);
	if (spacing < 0) return luaL_error(L, "glass container spacing must be nonnegative");
	UIGlassContainerEffect *effect = [[UIGlassContainerEffect alloc] init];
	effect.spacing = spacing;
	UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
	content.frame = view.contentView.bounds;
	content.autoresizingMask = UIViewAutoresizingFlexibleWidth
		| UIViewAutoresizingFlexibleHeight;
	[view.contentView addSubview:content];
	objc_setAssociatedObject(view, &kVisualEffectContentKey, content,
		OBJC_ASSOCIATION_RETAIN);
	[view sizeToFit];
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_UIKitControls_datePicker(lua_State *L) {
	UIDatePicker *picker = [[UIDatePicker alloc] initWithFrame:CGRectZero];
	picker.datePickerMode = UIDatePickerModeDate;
	picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
	if (!lua_isnoneornil(L, 1))
		picker.date = [NSDate dateWithTimeIntervalSince1970:luaL_checknumber(L, 1)];
	if (!lua_isnoneornil(L, 2)) {
		lua_reg_store(picker, &kCallbackKey, lua_reg_create(L, 2, YES));
		[picker addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
			forControlEvents:UIControlEventValueChanged];
	}
	[picker sizeToFit];
	push_objc(L, picker, "uiview");
	return 1;
}

static int bridge_UIKitControls_colorPicker(lua_State *L) {
	UIColorWell *well = [[UIColorWell alloc] initWithFrame:CGRectZero];
	if (!lua_isnoneornil(L, 1))
		well.selectedColor = lua_objc_uikit_system_color(luaL_checkstring(L, 1));
	if (!lua_isnoneornil(L, 2)) {
		lua_reg_store(well, &kCallbackKey, lua_reg_create(L, 2, YES));
		[well addTarget:[LuaButtonTarget shared] action:@selector(onAction:)
			forControlEvents:UIControlEventValueChanged];
	}
	[well sizeToFit];
	push_objc(L, well, "uiview");
	return 1;
}

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
	LuaReg *reg = objc_getAssociatedObject(pickerView, &kCallbackKey);
	lua_State *L = lua_reg_live_state(reg);
	if (!L || !lua_reg_push(reg)) return;
	push_objc(L, pickerView, "uiview");
	lua_objc_pcall(L, 1, 0, "picker");
}
@end

static int bridge_UIKitControls_vstack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"vstack", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_hstack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"hstack", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_flowStack(lua_State *L) {

	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"flow", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_zstack(lua_State *L) {
	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	objc_setAssociatedObject(obj, &kAxisKey, @"zstack", OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

@interface LuaUIKitScrollView : UIScrollView
@property (nonatomic, strong) UIView *luaContent;
@property (nonatomic) CGSize minimumContentSize;
@end

@implementation LuaUIKitScrollView
- (void)layoutSubviews {
	[super layoutSubviews];
	if (!self.luaContent) return;
	self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
	self.contentInset = UIEdgeInsetsZero;
	self.scrollIndicatorInsets = UIEdgeInsetsZero;
	CGSize viewport = self.bounds.size;
	CGFloat topInset = view_padding_top(self);
	CGSize measured = measure_size(self.luaContent, CGSizeMake(
		self.alwaysBounceHorizontal ? CGFLOAT_MAX : viewport.width,
		self.alwaysBounceVertical ? CGFLOAT_MAX : viewport.height));
	CGFloat minimumHeight = MAX(measured.height, self.minimumContentSize.height);
	CGSize content = CGSizeMake(
		self.alwaysBounceHorizontal ? MAX(viewport.width, MAX(measured.width, self.minimumContentSize.width)) : viewport.width,
		self.alwaysBounceVertical ? MAX(viewport.height, topInset + minimumHeight) : viewport.height);
	self.luaContent.frame = CGRectMake(0, topInset, content.width,
		MAX(minimumHeight, content.height - topInset));
	layout_recursive(self.luaContent, content.width);
	self.contentSize = content;

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
	scroll.minimumContentSize = CGSizeMake(contentWidth, contentHeight);
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
	objc_setAssociatedObject(obj, &kFlexBasisKey, @0, OBJC_ASSOCIATION_RETAIN);
	push_objc(L, obj, "uiview");
	return 1;
}

// UITextInputTraits are forwarded by UIKit and are not reliably KVC-settable.
// Expose a semantic editing mode on the exported controls instead.
static void set_verbatim_input(id<UITextInputTraits> input, BOOL verbatim) {
	input.autocorrectionType = verbatim ? UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault;
	input.autocapitalizationType = verbatim ? UITextAutocapitalizationTypeNone : UITextAutocapitalizationTypeSentences;
	input.smartQuotesType = verbatim ? UITextSmartQuotesTypeNo : UITextSmartQuotesTypeDefault;
	input.smartDashesType = verbatim ? UITextSmartDashesTypeNo : UITextSmartDashesTypeDefault;
	input.spellCheckingType = verbatim ? UITextSpellCheckingTypeNo : UITextSpellCheckingTypeDefault;
}

@interface LuaTextField : UITextField
@property(nonatomic) BOOL verbatim;
@end
@implementation LuaTextField
- (void)setVerbatim:(BOOL)value { _verbatim = value; set_verbatim_input(self, value); }
@end

@interface LuaTextView : UITextView
@property(nonatomic) BOOL verbatim;
@end
@implementation LuaTextView
- (void)setVerbatim:(BOOL)value { _verbatim = value; set_verbatim_input(self, value); }
@end

static int bridge_UIKitControls_textField(lua_State *L) {
	const char *text = luaL_optstring(L, 1, "");
	UITextField *obj = [[LuaTextField alloc] initWithFrame:CGRectZero];
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
	UITextView *obj = [[LuaTextView alloc] initWithFrame:CGRectZero];
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
	obj.numberOfLines = 0;
	obj.lineBreakMode = NSLineBreakByWordWrapping;
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_separator(lua_State *L) {
	const char *orientation = luaL_optstring(L, 1, "horizontal");
	BOOL vertical = strcmp(orientation, "vertical") == 0;
	UIView *obj = [[UIView alloc] initWithFrame:CGRectZero];
	obj.backgroundColor = UIColor.separatorColor;
	objc_setAssociatedObject(obj, vertical ? &kFixedWidthKey : &kFixedHeightKey,
		@(kSeparatorThickness),
		OBJC_ASSOCIATION_RETAIN);
	objc_setAssociatedObject(obj, vertical ? &kFillHeightKey : &kFillWidthKey, @YES,
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
	UIView *content = lua_isnoneornil(L, 7) ? nil : check_view(L, 7);
	UIFont *font = lua_isnoneornil(L, 6) ? nil : lua_to_objc_value(L, 6);
	BOOL has_callback = !lua_isnoneornil(L, 2);
	const char *style = luaL_optstring(L, 3, "default");
	const char *systemImage = luaL_optstring(L, 4, "");
	const char *role = luaL_optstring(L, 5, "");
	CGFloat symbolSize = (CGFloat)luaL_optnumber(L, 8, 0);
	const char *foregroundStyle = luaL_optstring(L, 9, "");
	const char *weightName = luaL_optstring(L, 10, "regular");
	LuaReg *callback = has_callback ? lua_reg_create(L, 2, YES) : nil;

	UIButton *obj = [UIButton buttonWithType:UIButtonTypeSystem];
	NSString *buttonTitle = [NSString stringWithUTF8String:title];
	UIButtonConfiguration *configuration = nil;
	if (strcmp(style, "bordered") == 0) {
		configuration = [UIButtonConfiguration borderedButtonConfiguration];
		configuration.baseForegroundColor = UIColor.tintColor;
	} else if (strcmp(style, "borderedProminent") == 0) {
		configuration = [UIButtonConfiguration borderedProminentButtonConfiguration];
	} else if (strcmp(style, "glass") == 0) {
		configuration = [UIButtonConfiguration glassButtonConfiguration];
	} else if (strcmp(style, "glassProminent") == 0) {
		configuration = [UIButtonConfiguration prominentGlassButtonConfiguration];
	} else if (strcmp(style, "default") == 0 || strcmp(style, "plain") == 0
		|| strcmp(style, "link") == 0) {
		configuration = [UIButtonConfiguration plainButtonConfiguration];
		configuration.contentInsets = NSDirectionalEdgeInsetsZero;
		configuration.baseForegroundColor = strcmp(style, "default") == 0
			? UIColor.tintColor : UIColor.labelColor;
		obj.contentHorizontalAlignment = buttonTitle.length == 0 && systemImage[0]
			? UIControlContentHorizontalAlignmentCenter
			: UIControlContentHorizontalAlignmentLeft;
	} else if (systemImage[0] || role[0]) {
		configuration = [UIButtonConfiguration plainButtonConfiguration];
	}
	if (configuration) {
		configuration.title = buttonTitle;
		// Configured buttons rebuild their title label; keep typography on the
		// configuration so state changes retain the requested font.
		if (font) configuration.attributedTitle = [[NSAttributedString alloc]
			initWithString:buttonTitle attributes:@{NSFontAttributeName:font}];
		if (systemImage[0])
			configuration.image = [UIImage systemImageNamed:
				[NSString stringWithUTF8String:systemImage]];
		if (symbolSize > 0)
			configuration.preferredSymbolConfigurationForImage =
				[UIImageSymbolConfiguration configurationWithPointSize:symbolSize
					weight:lua_objc_uikit_symbol_weight(weightName) scale:UIImageSymbolScaleMedium];
		if (foregroundStyle[0]) configuration.baseForegroundColor =
			strcmp(foregroundStyle, "accent") == 0
				? obj.tintColor : lua_objc_uikit_system_color(foregroundStyle);
		if (strcmp(role, "destructive") == 0) {
			if (strcmp(style, "borderedProminent") == 0) {
				configuration.baseBackgroundColor = UIColor.systemRedColor;
				configuration.baseForegroundColor = UIColor.whiteColor;
			} else {
				configuration.baseForegroundColor = UIColor.systemRedColor;
			}
		}
		obj.configuration = configuration;
	} else {
		[obj setTitle:buttonTitle forState:UIControlStateNormal];
		if (font) obj.titleLabel.font = font;
	}
	[obj sizeToFit];
	if (content) {
		content.userInteractionEnabled = NO;
		[obj addSubview:content];
		objc_setAssociatedObject(obj, &kButtonContentKey, content, OBJC_ASSOCIATION_RETAIN);
	}
	if (callback) {
		lua_reg_store(obj, &kCallbackKey, callback);
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

@interface LuaMenuStore : NSObject
@property (nonatomic, strong) NSArray<LuaReg *> *callbacks;
@end

@implementation LuaMenuStore
- (void)dealloc {
	for (LuaReg *reg in self.callbacks) [reg dispose];
}
@end

static int bridge_UIKitControls_menu(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	const char *buttonTitle = luaL_optstring(L, 2, "Menu");
	const char *systemImage = luaL_optstring(L, 3, "");
	const char *style = luaL_optstring(L, 4, "plain");
	CGFloat symbolSize = (CGFloat)luaL_optnumber(L, 5, kMenuSymbolPointSize);
	if (strcmp(style, "plain") != 0 && strcmp(style, "glass") != 0)
		return luaL_error(L, "menu style must be 'plain' or 'glass'");
	if (symbolSize <= 0) return luaL_error(L, "menu symbolSize must be positive");
	NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];
	NSMutableArray<LuaReg *> *regs = [NSMutableArray array];
	NSInteger count = (NSInteger)luaL_len(L, 1);
	for (NSInteger i = 1; i <= count; i++) {
		lua_rawgeti(L, 1, i);
		lua_getfield(L, -1, "title");
		const char *title = luaL_optstring(L, -1, "");
		lua_pop(L, 1);
		lua_getfield(L, -1, "systemImage");
		const char *symbol = luaL_optstring(L, -1, "");
		lua_pop(L, 1);
		lua_getfield(L, -1, "role");
		const char *role = luaL_optstring(L, -1, "");
		lua_pop(L, 1);
		lua_getfield(L, -1, "action");
		LuaReg *itemReg = nil;
		if (lua_isfunction(L, -1)) {
			itemReg = lua_reg_create(L, -1, YES);
			[regs addObject:itemReg];
		} else {
			lua_pop(L, 1);
		}
		UIAction *action = [UIAction actionWithTitle:[NSString stringWithUTF8String:title]
			image:(symbol[0] ? [UIImage systemImageNamed:[NSString stringWithUTF8String:symbol]] : nil)
			identifier:nil
			handler:^(__unused UIAction *selected) {
				if (!itemReg) return;
				lua_State *callL = lua_reg_live_state(itemReg);
				if (!callL || !lua_reg_push(itemReg)) return;
				lua_objc_pcall(callL, 0, 0, "menu");
			}];
		if (!itemReg) action.attributes = UIMenuElementAttributesDisabled;
		if (strcmp(role, "destructive") == 0)
			action.attributes |= UIMenuElementAttributesDestructive;
		[elements addObject:action];
		lua_pop(L, 1);
	}

	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *configuration = strcmp(style, "glass") == 0
		? [UIButtonConfiguration glassButtonConfiguration]
		: [UIButtonConfiguration plainButtonConfiguration];
	configuration.title = [NSString stringWithUTF8String:buttonTitle];
	configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	if (systemImage[0]) {
		configuration.image = [UIImage systemImageNamed:
			[NSString stringWithUTF8String:systemImage]];
		configuration.preferredSymbolConfigurationForImage =
			[UIImageSymbolConfiguration configurationWithPointSize:symbolSize
				weight:UIImageSymbolWeightRegular scale:UIImageSymbolScaleMedium];
	}
	button.configuration = configuration;
	button.menu = [UIMenu menuWithTitle:@"" children:elements];
	button.showsMenuAsPrimaryAction = YES;
	LuaMenuStore *store = [[LuaMenuStore alloc] init];
	store.callbacks = regs;
	objc_setAssociatedObject(button, &kTableSourceKey, store,
		OBJC_ASSOCIATION_RETAIN);
	[button sizeToFit];
	push_objc(L, button, "uiview");
	return 1;
}

static int bridge_UIKitControls_toggle(lua_State *L) {
	const char *label = luaL_checkstring(L, 1);
	BOOL is_on = (BOOL)lua_toboolean(L, 2);
	LuaReg *callback = lua_reg_opt(L, 3);

	UISwitch *obj = [[UISwitch alloc] initWithFrame:CGRectZero];
	obj.on = is_on;
	obj.accessibilityLabel = [NSString stringWithUTF8String:label];
	[obj sizeToFit];
	if (callback) {
		lua_reg_store(obj, &kCallbackKey, callback);
		[obj addTarget:[LuaButtonTarget shared] action:@selector(onAction:) forControlEvents:UIControlEventValueChanged];
	}
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_UIKitControls_slider(lua_State *L) {
	CGFloat minimum = luaL_optnumber(L, 1, 0);
	CGFloat maximum = luaL_optnumber(L, 2, 1);
	CGFloat value = luaL_optnumber(L, 3, minimum);
	LuaReg *callback = lua_reg_opt(L, 4);

	UISlider *obj = [[UISlider alloc] initWithFrame:CGRectZero];
	obj.minimumValue = minimum;
	obj.maximumValue = MAX(minimum, maximum);
	obj.value = MIN(MAX(value, minimum), obj.maximumValue);
	[obj sizeToFit];
	if (callback) {
		lua_reg_store(obj, &kCallbackKey, callback);
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
	LuaReg *callback = lua_reg_opt(L, 5);

	UIStepper *obj = [[UIStepper alloc] initWithFrame:CGRectZero];
	obj.minimumValue = minimum;
	obj.maximumValue = MAX(minimum, maximum);
	obj.stepValue = MAX(0, step);
	obj.value = MIN(MAX(value, minimum), obj.maximumValue);
	[obj sizeToFit];
	if (callback) {
		lua_reg_store(obj, &kCallbackKey, callback);
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
	const char *style = luaL_optstring(L, 4, "automatic");
	LuaReg *callback = lua_reg_opt(L, 3);
	if (strcmp(style, "segmented") == 0) {
		UISegmentedControl *segmented = [[UISegmentedControl alloc]
			initWithItems:options];
		segmented.selectedSegmentIndex = selected;
		if (callback) {
			lua_reg_store(segmented, &kCallbackKey, callback);
			[segmented addTarget:[LuaButtonTarget shared]
				action:@selector(onAction:)
				forControlEvents:UIControlEventValueChanged];
		}
		[segmented sizeToFit];
		push_objc(L, segmented, "uiview");
		return 1;
	}
	if (strcmp(style, "wheel") != 0 && strcmp(style, "menu") != 0
		&& strcmp(style, "automatic") != 0)
		return luaL_error(L, "Picker style must be segmented, menu, wheel, or automatic");
	if (strcmp(style, "menu") == 0 || strcmp(style, "automatic") == 0) {
		NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];
		for (NSInteger i = 0; i < count; i++) {
			NSInteger index = i;
			UIAction *action = [UIAction actionWithTitle:options[i] image:nil
				identifier:nil handler:^(__unused UIAction *selectedAction) {
					lua_State *callL = lua_reg_live_state(callback);
					if (!callL || !lua_reg_push(callback)) return;
					lua_pushinteger(callL, index);
					lua_objc_pcall(callL, 1, 0, "picker");
				}];
			[elements addObject:action];
		}
		UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
		[button setTitle:options[selected] forState:UIControlStateNormal];
		button.menu = [UIMenu menuWithTitle:@"" children:elements];
		button.showsMenuAsPrimaryAction = YES;
		if (callback) lua_reg_store(button, &kCallbackKey, callback);
		[button sizeToFit];
		push_objc(L, button, "uiview");
		return 1;
	}

	UIPickerView *obj = [[UIPickerView alloc] initWithFrame:CGRectZero];
	LuaPickerDataSource *source = [[LuaPickerDataSource alloc] init];
	source.options = options;
	obj.dataSource = source;
	obj.delegate = source;
	[obj selectRow:(NSUInteger)selected inComponent:0 animated:NO];
	objc_setAssociatedObject(obj, &kTableSourceKey, source, OBJC_ASSOCIATION_RETAIN);
	if (callback) lua_reg_store(obj, &kCallbackKey, callback);
	[obj sizeToFit];
	push_objc(L, obj, "uiview");
	return 1;
}

static int bridge_hit_test_target(lua_State *L) {
	UIView *view = check_view(L, 1);
	UIView *target = check_view(L, 2);
	CGPoint point = CGPointMake(luaL_checknumber(L, 3), luaL_checknumber(L, 4));
	lua_pushboolean(L, [view hitTest:point withEvent:nil] == target);
	return 1;
}
