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


static int bridge_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	NSString *nsPath = [NSString stringWithUTF8String:path];

	UIImage *img = [UIImage imageWithContentsOfFile:nsPath];
	if (!img) img = [UIImage imageNamed:nsPath];
	if (!img) return luaL_error(L, "failed to load image: %s", path);

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

#include <math.h>

static CGFloat arc_normalize_degrees(CGFloat degrees) {
	CGFloat wrapped = fmod(degrees, 360.0);
	if (wrapped < 0) wrapped += 360.0;
	return wrapped;
}

static void arc_add_clockwise(UIBezierPath *path, CGPoint center, CGFloat radius,
		CGFloat startDegrees, CGFloat sweepDegrees) {
	CGFloat angle = startDegrees;
	CGFloat remaining = sweepDegrees;
	BOOL moved = !path.isEmpty;
	while (remaining > 0.01) {
		CGFloat step = MIN(90.0, remaining);
		CGFloat a1 = angle * M_PI / 180.0;
		CGFloat a2 = (angle + step) * M_PI / 180.0;
		CGFloat handle = (4.0 / 3.0) * tan((a2 - a1) / 4.0);
		CGPoint start = CGPointMake(center.x + radius * cos(a1), center.y + radius * sin(a1));
		CGPoint end = CGPointMake(center.x + radius * cos(a2), center.y + radius * sin(a2));
		CGPoint tangentStart = CGPointMake(-sin(a1), cos(a1));
		CGPoint tangentEnd = CGPointMake(-sin(a2), cos(a2));
		if (!moved) {
			[path moveToPoint:start];
			moved = YES;
		}
		[path addCurveToPoint:end
			controlPoint1:CGPointMake(start.x + handle * radius * tangentStart.x,
				start.y + handle * radius * tangentStart.y)
			controlPoint2:CGPointMake(end.x - handle * radius * tangentEnd.x,
				end.y - handle * radius * tangentEnd.y)];
		angle += step;
		remaining -= step;
	}
}

@interface LuaArcView ()
@property(nonatomic) CGFloat startAngle;
@property(nonatomic) CGFloat endAngle;
@property(nonatomic) CGFloat lineWidth;
@property(nonatomic) CGFloat strokeAlpha;
@property(nonatomic, copy) NSString *stroke;
@property(nonatomic, copy) NSString *lineCap;
- (UIBezierPath *)arcPath;
@end

/* SwiftUI strokes a shape centered on its path and never clips it to the
 * frame, so an Arc stroke extends lineWidth/2 past its bounds. drawRect is
 * clipped to the view's backing store; a CAShapeLayer is not. */
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

- (UIBezierPath *)arcPath {
	CGRect bounds = self.bounds;
	CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
	CGFloat radius = MIN(bounds.size.width, bounds.size.height) / 2.0;
	UIBezierPath *path = [UIBezierPath bezierPath];
	if (radius <= 0) return path;
	CGFloat start = arc_normalize_degrees(self.startAngle);
	CGFloat end = arc_normalize_degrees(self.endAngle);
	CGFloat sweep = end - start;
	if (sweep <= 0) sweep += 360.0;
	if (sweep >= kArcFullCircleDegrees) {
		[path appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(
			center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)]];
	} else {
		arc_add_clockwise(path, center, radius, start, sweep);
	}
	path.lineWidth = self.lineWidth;
	path.lineCapStyle = [self.lineCap isEqualToString:@"round"] ? kCGLineCapRound : kCGLineCapButt;
	return path;
}

- (void)updateShape {
	CAShapeLayer *shape = (CAShapeLayer *)self.layer;
	shape.path = self.arcPath.CGPath;
	shape.fillColor = nil;
	shape.lineWidth = self.lineWidth;
	shape.lineCap = [self.lineCap isEqualToString:@"round"] ? kCALineCapRound : kCALineCapButt;
	// Label colors carry their own translucency; strokeAlpha scales it.
	UIColor *color = [lua_objc_uikit_system_color((self.stroke ?: @"accent").UTF8String)
		resolvedColorWithTraitCollection:self.traitCollection];
	shape.strokeColor = [color colorWithAlphaComponent:
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

@end

static int bridge_arc(lua_State *L) {
	CGFloat width = (CGFloat)luaL_optnumber(L, 1, 48);
	CGFloat height = (CGFloat)luaL_optnumber(L, 2, width);
	LuaArcView *view = [[LuaArcView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_LuaArcView_arcBounds(lua_State *L) {
	LuaArcView *view = lua_objc_check_object(L, 1, [LuaArcView class], "Arc");
	push_CGRect(L, view.arcPath.bounds);
	return 1;
}
