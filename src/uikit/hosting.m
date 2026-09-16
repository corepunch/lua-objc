#pragma mark - Scene hosting

__attribute__((weak)) UIWindow *LRTApplicationWindow(void) {
	return nil;
}

@interface LuaHostingController : UIViewController
@property (nonatomic, strong) UIView *luaRoot;
@end

@implementation LuaHostingController
- (instancetype)initWithLuaView:(UIView *)view {
	self = [super initWithNibName:nil bundle:nil];
	_luaRoot = view;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	if (!self.luaRoot) return;
	[self.view addSubview:self.luaRoot];
	NSString *safeArea = self.luaRoot.ignoresSafeArea;
	BOOL ignoresTop = [safeArea isEqualToString:@"top"]
		|| [safeArea isEqualToString:@"all"]
		|| [safeArea isEqualToString:@"edges"];
	self.luaRoot.translatesAutoresizingMaskIntoConstraints = NO;
	// Referencing the keyboard guide from constraints lets UIKit drive updates
	// during keyboard transitions, including sheets and hardware keyboards.
	[NSLayoutConstraint activateConstraints:@[
		[self.luaRoot.topAnchor constraintEqualToAnchor:ignoresTop ? self.view.topAnchor : self.view.safeAreaLayoutGuide.topAnchor],
		[self.luaRoot.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
		[self.luaRoot.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
		[self.luaRoot.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
	]];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	layout_recursive(self.luaRoot, self.luaRoot.bounds.size.width);
}
@end

static UIViewController *check_view_controller(lua_State *L, int idx) {
	ObjCRef *ref = luaL_testudata(L, idx, "uiviewcontroller");
	if (ref) {
		id obj = (__bridge id)ref->ptr;
		if ([obj isKindOfClass:[UIViewController class]]) return obj;
	}
	id obj = check_objc(L, idx);
	if ([obj isKindOfClass:[UIViewController class]]) return obj;
	if ([obj isKindOfClass:[UIView class]]) {
		return [[LuaHostingController alloc] initWithLuaView:(UIView *)obj];
	}
	luaL_typeerror(L, idx, "uiviewcontroller or uiview");
	return nil;
}

static int bridge_hosting_controller(lua_State *L) {
	id obj = check_objc(L, 1);
	if ([obj isKindOfClass:[UIViewController class]]) {
		push_objc(L, obj, "uiviewcontroller");
		return 1;
	}
	if (![obj isKindOfClass:[UIView class]]) {
		luaL_typeerror(L, 1, "uiview or uiviewcontroller");
	}
	UIView *view = (UIView *)obj;
	LuaHostingController *vc =
		[[LuaHostingController alloc] initWithLuaView:view];
	push_objc(L, vc, "uiviewcontroller");
	return 1;
}

static int bridge_install_scene(lua_State *L) {
	UIViewController *root = check_view_controller(L, 1);
	const char *title = luaL_optstring(L, 2, "");
	UIWindow *window = LRTApplicationWindow();
	if (!window) {
		return luaL_error(L, "UIKit.Window requires an attached UIWindowScene");
	}
	window.rootViewController = root;
	window.accessibilityLabel = @(title);
	[window makeKeyAndVisible];
	push_objc(L, window, "uiwindow");
	return 1;
}
