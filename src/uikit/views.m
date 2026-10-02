#pragma mark - Bridge functions (UIKit)

@interface LuaGestureTarget : NSObject
@property (nonatomic, strong) LuaReg *callback;
- (void)tap:(UITapGestureRecognizer *)recognizer;
- (void)drag:(UIPanGestureRecognizer *)recognizer;
- (void)edgeSwipe:(UIScreenEdgePanGestureRecognizer *)recognizer;
@end

@implementation LuaGestureTarget
- (void)fire:(UIGestureRecognizer *)recognizer state:(NSString *)state {
	lua_State *L = lua_reg_live_state(self.callback);
	if (!L || !lua_reg_push(self.callback)) return;
	lua_newtable(L);
	lua_pushstring(L, state.UTF8String); lua_setfield(L, -2, "state");
	CGPoint location = [recognizer locationInView:recognizer.view];
	lua_newtable(L); lua_pushnumber(L, location.x); lua_setfield(L, -2, "x");
	lua_pushnumber(L, location.y); lua_setfield(L, -2, "y"); lua_setfield(L, -2, "location");
	if ([recognizer isKindOfClass:UIPanGestureRecognizer.class]) {
		UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)recognizer;
		CGPoint translation = [pan translationInView:pan.view];
		CGPoint velocity = [pan velocityInView:pan.view];
		lua_newtable(L); lua_pushnumber(L, translation.x); lua_setfield(L, -2, "x");
		lua_pushnumber(L, translation.y); lua_setfield(L, -2, "y"); lua_setfield(L, -2, "translation");
		lua_newtable(L); lua_pushnumber(L, velocity.x); lua_setfield(L, -2, "x");
		lua_pushnumber(L, velocity.y); lua_setfield(L, -2, "y"); lua_setfield(L, -2, "velocity");
	}
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) report_lua_error(L, "gesture callback");
}
- (void)tap:(UITapGestureRecognizer *)recognizer {
	(void)recognizer;
	lua_State *L = lua_reg_live_state(self.callback);
	if (L && lua_reg_push(self.callback)) lua_objc_pcall(L, 0, 0, "tap gesture");
}
- (void)drag:(UIPanGestureRecognizer *)recognizer {
	NSString *state = @"changed";
	if (recognizer.state == UIGestureRecognizerStateBegan) state = @"began";
	else if (recognizer.state == UIGestureRecognizerStateEnded) state = @"ended";
	else if (recognizer.state == UIGestureRecognizerStateCancelled) state = @"cancelled";
	[self fire:recognizer state:state];
}
- (void)edgeSwipe:(UIScreenEdgePanGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateEnded) return;
	CGPoint movement = [recognizer translationInView:recognizer.view];
	if (movement.x < kEdgeSwipeBackDistance ||
		movement.x <= fabs(movement.y) * kEdgeSwipeHorizontalRatio) return;
	lua_State *L = lua_reg_live_state(self.callback);
	if (L && lua_reg_push(self.callback)) lua_objc_pcall(L, 0, 0, "edge swipe");
}
@end

static int bridge_UIKit_addTap(lua_State *L) {
	UIView *view = check_view(L, 1);
	LuaReg *callback = lua_reg_opt(L, 2);
	if (!callback) return 0;
	LuaGestureTarget *target = [LuaGestureTarget new]; target.callback = callback;
	UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(tap:)];
	recognizer.cancelsTouchesInView = NO;
	[view addGestureRecognizer:recognizer]; view.userInteractionEnabled = YES;
	objc_setAssociatedObject(recognizer, &kCallbackKey, target, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_UIKit_addDrag(lua_State *L) {
	UIView *view = check_view(L, 1);
	LuaReg *callback = lua_reg_opt(L, 2);
	if (!callback) return 0;
	LuaGestureTarget *target = [LuaGestureTarget new]; target.callback = callback;
	UIPanGestureRecognizer *recognizer = [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(drag:)];
	[view addGestureRecognizer:recognizer];
	objc_setAssociatedObject(recognizer, &kCallbackKey, target, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_UIKit_addEdgeSwipe(lua_State *L) {
	UIView *view = check_view(L, 1);
	LuaReg *callback = lua_reg_opt(L, 2);
	if (!callback) return 0;
	LuaGestureTarget *target = [LuaGestureTarget new]; target.callback = callback;
	UIScreenEdgePanGestureRecognizer *recognizer = [[UIScreenEdgePanGestureRecognizer alloc]
		initWithTarget:target action:@selector(edgeSwipe:)];
	recognizer.edges = UIRectEdgeLeft;
	[view addGestureRecognizer:recognizer];
	objc_setAssociatedObject(recognizer, &kCallbackKey, target, OBJC_ASSOCIATION_RETAIN);
	return 0;
}

static int bridge_window(lua_State *L) {
	const char *title = luaL_checkstring(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	UIWindowScene *windowScene = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if ([scene isKindOfClass:[UIWindowScene class]]
			&& scene.activationState != UISceneActivationStateUnattached) {
			windowScene = (UIWindowScene *)scene;
			break;
		}
	}
	if (!windowScene) {
		return luaL_error(L, "UIKit.Window requires an attached UIWindowScene");
	}

	CGRect frame = CGRectMake(0, 0, width, height);
	UIWindow *w = [[UIWindow alloc] initWithWindowScene:windowScene];
	w.frame = frame;
	w.backgroundColor = UIColor.systemBackgroundColor;
	w.accessibilityLabel = [NSString stringWithUTF8String:title];

	push_objc(L, w, "uiwindow");
	return 1;
}


/* `darkPath`: the image shown under a dark appearance, as an asset
 * catalog's dark variant is. Both are registered with one image asset, and
 * the image view picks the one for its traits whenever they change. */
static UIImage *lua_objc_uikit_appearance_image(UIImage *light, UIImage *dark) {
	UIImageAsset *asset = [[UIImageAsset alloc] init];
	[asset registerImage:light withTraitCollection:
		[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]];
	[asset registerImage:dark withTraitCollection:
		[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
	return [asset imageWithTraitCollection:UITraitCollection.currentTraitCollection];
}

static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];

	UIImage *img = [UIImage imageWithContentsOfFile:nsPath];
	if (!img) img = [UIImage imageNamed:nsPath];
	if (!img) return luaL_error(L, "failed to load image: %s", path);
	if (lua_isstring(L, 2)) {
		NSString *darkPath = @(lua_tostring(L, 2));
		UIImage *dark = [UIImage imageWithContentsOfFile:darkPath] ?: [UIImage imageNamed:darkPath];
		if (!dark) return luaL_error(L, "failed to load image: %s", darkPath.UTF8String);
		img = lua_objc_uikit_appearance_image(img, dark);
	}

	CGSize size = img.size;
	if (size.width > kImageMaxWidth) {
		CGFloat ratio = kImageMaxWidth / size.width;
		size.width = kImageMaxWidth;
		size.height *= ratio;
	}

	UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
	iv.image = img;
	iv.contentMode = UIViewContentModeScaleAspectFit;
	/* Keep layout measurement tied to the bridge's proportional display size,
	 * rather than UIImageView's uncapped intrinsic image size. */
	objc_setAssociatedObject(iv, &kImageLayoutSizeKey,
		[NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN);

	push_objc(L, iv, "uiview");
	return 1;
}

static UIColor *lua_objc_uikit_system_color(const char *name) {
	if (!name) return UIColor.labelColor;
	/* "light|dark" pairs resolve against the trait collection, like an
	 * asset-catalog colour with Any and Dark variants. */
	const char *bar = strchr(name, '|');
	if (bar) {
		NSString *pair = @(name);
		NSRange split = [pair rangeOfString:@"|"];
		UIColor *light = lua_objc_uikit_system_color([pair substringToIndex:split.location].UTF8String);
		UIColor *dark = lua_objc_uikit_system_color([pair substringFromIndex:NSMaxRange(split)].UTF8String);
		return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
			return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
		}];
	}
	if (name[0] == '#' && strlen(name + 1) == 6) {
		char *end = NULL;
		unsigned long rgb = strtoul(name + 1, &end, 16);
		if (end && *end == '\0') {
			return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
				green:((rgb >> 8) & 0xff) / 255.0
				blue:(rgb & 0xff) / 255.0 alpha:1.0];
		}
	}
	if (strcmp(name, "clear") == 0) return UIColor.clearColor;
	if (strcmp(name, "systemRed") == 0) return UIColor.systemRedColor;
	if (strcmp(name, "systemGreen") == 0) return UIColor.systemGreenColor;
	if (strcmp(name, "systemBlue") == 0) return UIColor.systemBlueColor;
	if (strcmp(name, "systemOrange") == 0) return UIColor.systemOrangeColor;
	if (strcmp(name, "systemPurple") == 0) return UIColor.systemPurpleColor;
	if (strcmp(name, "systemPink") == 0) return UIColor.systemPinkColor;
	if (strcmp(name, "systemTeal") == 0) return UIColor.systemTealColor;
	if (strcmp(name, "systemIndigo") == 0) return UIColor.systemIndigoColor;
	if (strcmp(name, "systemMint") == 0) return UIColor.systemMintColor;
	if (strcmp(name, "systemCyan") == 0) return UIColor.systemCyanColor;
	if (strcmp(name, "systemBrown") == 0) return UIColor.systemBrownColor;
	if (strcmp(name, "systemGray") == 0) return UIColor.systemGrayColor;
	if (strcmp(name, "systemYellow") == 0) return UIColor.systemYellowColor;
	if (strcmp(name, "secondary") == 0) return UIColor.secondaryLabelColor;
	if (strcmp(name, "tertiary") == 0) return UIColor.tertiaryLabelColor;
	if (strcmp(name, "quaternaryLabel") == 0) return UIColor.quaternaryLabelColor;
	if (strcmp(name, "accent") == 0) return UIColor.tintColor;
	if (strcmp(name, "red") == 0) return UIColor.systemRedColor;
	if (strcmp(name, "blue") == 0) return UIColor.systemBlueColor;
	if (strcmp(name, "green") == 0) return UIColor.systemGreenColor;
	if (strcmp(name, "primary") == 0) return UIColor.labelColor;
	if (strcmp(name, "white") == 0) return UIColor.whiteColor;
	if (strcmp(name, "yellow") == 0) return UIColor.systemYellowColor;
	if (strcmp(name, "separator") == 0) return UIColor.separatorColor;
	if (strcmp(name, "secondaryBackground") == 0) return UIColor.secondarySystemBackgroundColor;
	if (strcmp(name, "background") == 0) return UIColor.systemBackgroundColor;
	return UIColor.labelColor;
}

static int bridge_image_data(lua_State *L) {
	size_t len = 0;
	const char *bytes = luaL_checklstring(L, 1, &len);
	NSData *data = [NSData dataWithBytes:bytes length:len];
	UIImage *img = [UIImage imageWithData:data];
	if (!img) return luaL_error(L, "failed to decode image data");
	if (lua_isstring(L, 2)) {
		size_t darkLen = 0;
		const char *darkBytes = lua_tolstring(L, 2, &darkLen);
		UIImage *dark = [UIImage imageWithData:[NSData dataWithBytes:darkBytes length:darkLen]];
		if (!dark) return luaL_error(L, "failed to decode dark image data");
		img = lua_objc_uikit_appearance_image(img, dark);
	}
	CGSize size = img.size;
	if (size.width > kImageMaxWidth) {
		CGFloat ratio = kImageMaxWidth / size.width;
		size.width = kImageMaxWidth;
		size.height *= ratio;
	}
	UIImageView *iv = [[UIImageView alloc]
		initWithFrame:CGRectMake(0, 0, size.width, size.height)];
	iv.image = img;
	iv.contentMode = UIViewContentModeScaleAspectFit;
	objc_setAssociatedObject(iv, &kImageLayoutSizeKey,
		[NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN);
	push_objc(L, iv, "uiview");
	return 1;
}

static UIImageSymbolWeight lua_objc_uikit_symbol_weight(const char *weightName) {
	UIImageSymbolWeight weight = UIImageSymbolWeightRegular;
	if (strcmp(weightName, "bold") == 0) weight = UIImageSymbolWeightBold;
	else if (strcmp(weightName, "semibold") == 0)
		weight = UIImageSymbolWeightSemibold;
	else if (strcmp(weightName, "light") == 0)
		weight = UIImageSymbolWeightLight;
	else if (strcmp(weightName, "heavy") == 0)
		weight = UIImageSymbolWeightHeavy;
	return weight;
}

static int bridge_system_image(lua_State *L) {
	const char *symbol = luaL_checkstring(L, 1);
	const char *description = luaL_optstring(L, 2, symbol);
	CGFloat pointSize = luaL_optnumber(L, 3, 17);
	const char *weightName = luaL_optstring(L, 4, "regular");
	const char *colorName = luaL_optstring(L, 5, "accent");

	UIImageSymbolConfiguration *configuration =
		[UIImageSymbolConfiguration configurationWithPointSize:pointSize
			weight:lua_objc_uikit_symbol_weight(weightName) scale:UIImageSymbolScaleMedium];
	UIImage *image = [UIImage systemImageNamed:
		[NSString stringWithUTF8String:symbol]
		withConfiguration:configuration];
	if (!image) return luaL_error(L, "unknown SF Symbol: %s", symbol);

	UIImageView *view = [[UIImageView alloc]
		initWithFrame:CGRectMake(0, 0, pointSize, pointSize)];
	view.image = image;
	view.contentMode = UIViewContentModeScaleAspectFit;
	view.tintColor = lua_objc_uikit_system_color(colorName);
	view.accessibilityLabel = [NSString stringWithUTF8String:description];
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_system_color(lua_State *L) {
	const char *name = luaL_checkstring(L, 1);
	push_objc(L, lua_objc_uikit_system_color(name), "nsobject");
	return 1;
}

static int bridge_add(lua_State *L) {
	id parent = check_objc(L, 1);
	UIView *child = check_view(L, 2);

	if ([parent isKindOfClass:[UIWindow class]]) {
		UIWindow *window = (UIWindow *)parent;
		[window addSubview:child];
		child.frame = window.bounds;
		child.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	} else {
		UIView *container = (UIView *)parent;
		motion_will_change(container, YES);
		[container addSubview:child];
		uikit_invalidate_layout(container);
	}

	return 0;
}

static int bridge_layout(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_optnumber(L, 2, 400);

	UIView *view = (UIView *)obj;
	layout_recursive(view, width);
	return 0;
}

static int bridge_clear_container(lua_State *L) {
	UIView *container = check_objc(L, 1);
	for (UIView *child in [container.subviews copy]) [child removeFromSuperview];
	uikit_invalidate_layout(container);
	return 0;
}

static int bridge_set_content_size(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);

	UIView *v = (UIView *)obj;
	v.frame = CGRectMake(v.frame.origin.x, v.frame.origin.y, width, height);
	return 0;
}

static int bridge_size_to_fit(lua_State *L) {
	UIView *view = check_view(L, 1);
	[view sizeToFit];
	return 0;
}

#pragma mark - Window close (scope teardown)

/* Mirrors AppKit's NSWindowWillClose → scope:close() contract. The helper is
 * retained by the UIWindow; when the window deallocs (scene teardown) the
 * helper deallocs, invokes the Lua close callback once, and disposes it. */
@interface LuaWindowCloseHelper : NSObject
@property (nonatomic, strong) LuaReg *closeReg;
@end

@implementation LuaWindowCloseHelper
- (void)dealloc {
	LuaReg *reg = _closeReg;
	_closeReg = nil;
	lua_State *callL = lua_reg_live_state(reg);
	if (callL && lua_reg_push(reg))
		lua_objc_pcall(callL, 0, 0, "window close");
	[reg dispose];
}
@end

static int bridge_on_window_close(lua_State *L) {
	ObjCRef *ref = lua_objc_test_ref(L, 1);
	if (!ref) return luaL_typeerror(L, 1, "UIWindow");
	id obj = lua_objc_live_ptr(L, 1, ref);
	if (![obj isKindOfClass:[UIWindow class]])
		return luaL_error(L, "onWindowClose requires a window");
	UIWindow *window = (UIWindow *)obj;
	LuaWindowCloseHelper *existing = objc_getAssociatedObject(window, &kWindowCloseKey);
	if (!existing) {
		existing = [[LuaWindowCloseHelper alloc] init];
		objc_setAssociatedObject(window, &kWindowCloseKey, existing,
			OBJC_ASSOCIATION_RETAIN);
	}
	existing.closeReg = lua_reg_opt_unscoped(L, 2);
	return 0;
}

/* An arc or sector (shared/arc_path.m) as a filled CAShapeLayer path. Its
 * shape animates inside a transaction (LuaMotionShape), so a chart's
 * sectors turn and grow along their circles rather than morphing point by
 * point. The layer is not clipped: SwiftUI never clips a stroke to its
 * frame. */
@interface LuaArcView () <LuaMotionShape>
@property(nonatomic) CGFloat startAngle;
@property(nonatomic) CGFloat endAngle;
@property(nonatomic) CGFloat lineWidth;
@property(nonatomic) CGFloat strokeAlpha;
@property(nonatomic, copy) NSString *stroke;
@property(nonatomic, copy) NSString *lineCap;
@property(nonatomic) CGFloat diameter;
@property(nonatomic) CGFloat fitDiameter;
@property(nonatomic) CGFloat inset;
@property(nonatomic) CGFloat cornerRadius;
- (ArcShape)shape;
@end

@implementation LuaArcView

+ (Class)layerClass { return CAShapeLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_lineWidth = 1;
		_strokeAlpha = 1;
		_stroke = @"accent";
		_lineCap = @"butt";
		self.backgroundColor = UIColor.clearColor;
		self.opaque = NO;
		self.clipsToBounds = NO;
		self.userInteractionEnabled = NO;
		[self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
			withAction:@selector(updateShape)];
		[self updateShape];
	}
	return self;
}

- (ArcShape)shape {
	return (ArcShape){self.startAngle, self.endAngle, self.lineWidth, self.diameter, self.fitDiameter,
		self.inset, self.cornerRadius, [self.lineCap isEqualToString:@"round"]};
}

- (id)motionShape { return arc_shape_value(self.shape); }

- (CGPathRef)copyMotionPathFrom:(id)from progress:(CGFloat)progress {
	return arc_path_create(self.bounds, arc_shape_mix(arc_shape_from_value(from), self.shape, progress));
}

- (void)updateShape {
	CAShapeLayer *layer = (CAShapeLayer *)self.layer;
	CGPathRef path = arc_path_create(self.bounds, self.shape);
	layer.path = path;
	if (path) CGPathRelease(path);
	layer.fillRule = kCAFillRuleEvenOdd;
	// Label colors carry their own translucency; strokeAlpha scales it.
	UIColor *color = [lua_objc_uikit_system_color((self.stroke ?: @"accent").UTF8String)
		resolvedColorWithTraitCollection:self.traitCollection];
	layer.fillColor = [color colorWithAlphaComponent:
		CGColorGetAlpha(color.CGColor) * MIN(1, MAX(0, self.strokeAlpha))].CGColor;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self updateShape];
}

- (void)setStartAngle:(CGFloat)value { _startAngle = value; [self updateShape]; }
- (void)setEndAngle:(CGFloat)value { _endAngle = value; [self updateShape]; }
- (void)setLineWidth:(CGFloat)value { _lineWidth = value; [self updateShape]; }
- (void)setStrokeAlpha:(CGFloat)value { _strokeAlpha = value; [self updateShape]; }
- (void)setStroke:(NSString *)value { _stroke = [value copy]; [self updateShape]; }
- (void)setLineCap:(NSString *)value { _lineCap = [value copy]; [self updateShape]; }
- (void)setDiameter:(CGFloat)value { _diameter = value; [self updateShape]; }
- (void)setFitDiameter:(CGFloat)value { _fitDiameter = value; [self updateShape]; }
- (void)setInset:(CGFloat)value { _inset = value; [self updateShape]; }
- (void)setCornerRadius:(CGFloat)value { _cornerRadius = value; [self updateShape]; }

@end

static int bridge_arc(lua_State *L) {
	CGFloat width = (CGFloat)luaL_optnumber(L, 1, 48);
	CGFloat height = (CGFloat)luaL_optnumber(L, 2, width);
	LuaArcView *view = [[LuaArcView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	push_objc(L, view, "uiview");
	return 1;
}

// The drawn outline's bounds in view coordinates.
static int bridge_LuaArcView_arcBounds(lua_State *L) {
	LuaArcView *view = lua_objc_check_object(L, 1, [LuaArcView class], "Arc");
	CGPathRef path = arc_path_create(view.bounds, view.shape);
	push_CGRect(L, path ? CGPathGetPathBoundingBox(path) : CGRectZero);
	if (path) CGPathRelease(path);
	return 1;
}
