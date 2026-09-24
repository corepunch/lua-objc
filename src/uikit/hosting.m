#pragma mark - Scene hosting

__attribute__((weak)) UIWindow *LRTApplicationWindow(void) {
	return nil;
}

@interface LuaHostingController : UIViewController
@property (nonatomic, strong) UIView *luaRoot;
@property (nonatomic, strong) LuaReg *disappearCallback;
@end

@implementation LuaHostingController
- (BOOL)ignoresTopSafeArea {
	NSString *safeArea = self.luaRoot.ignoresSafeArea;
	return [safeArea isEqualToString:@"top"]
		|| [safeArea isEqualToString:@"all"]
		|| [safeArea isEqualToString:@"edges"];
}

- (void)updateHostSafeAreaPadding {
	CGFloat topInset = [self ignoresTopSafeArea] ? 0 : self.view.safeAreaInsets.top;
	objc_setAssociatedObject(self.luaRoot, &kHostSafeAreaTopKey, @(topInset),
		OBJC_ASSOCIATION_RETAIN);
	[self updateBottomSafeAreaPaddingInView:self.luaRoot];
}

- (void)updateBottomSafeAreaPaddingInView:(UIView *)view {
	if (view.safeAreaInsetBottom) {
		CGFloat bottomInset = self.view.safeAreaInsets.bottom;
		UITabBar *tabBar = self.tabBarController.tabBar;
		if (tabBar && !tabBar.hidden && tabBar.window == self.view.window) {
			CGRect tabFrame = [tabBar.superview convertRect:tabBar.frame toView:self.view];
			// The hosted root already ends where the external tab bar begins.
			if (CGRectGetMinY(tabFrame) >= CGRectGetMaxY(self.luaRoot.frame) - 1)
				bottomInset = 0;
		}
		objc_setAssociatedObject(view, &kHostSafeAreaBottomKey,
			@(bottomInset), OBJC_ASSOCIATION_RETAIN);
	}
	for (UIView *child in view.subviews) {
		[self updateBottomSafeAreaPaddingInView:child];
	}
}

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
	self.luaRoot.translatesAutoresizingMaskIntoConstraints = NO;
	// The Lua root owns the full window so safe-area regions keep the app
	// background. Insets are handed to the layout engine.
	[NSLayoutConstraint activateConstraints:@[
		[self.luaRoot.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.luaRoot.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.luaRoot.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.luaRoot.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
	]];
}

- (void)viewSafeAreaInsetsDidChange {
	[super viewSafeAreaInsetsDidChange];
	[self updateHostSafeAreaPadding];
	[self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updateHostSafeAreaPadding];
	layout_recursive(self.luaRoot, self.luaRoot.bounds.size.width);
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	if (!self.isMovingFromParentViewController && !self.isBeingDismissed) return;
	LuaReg *callback = self.disappearCallback;
	self.disappearCallback = nil;
	if (!callback) return;
	lua_State *L = lua_reg_live_state(callback);
	if (L && lua_reg_push(callback))
		lua_objc_pcall(L, 0, 0, "hosting controller disappear");
	[callback dispose];
}

- (void)dealloc {
	[_disappearCallback dispose];
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
	BOOL hidesNavigationBar = lua_toboolean(L, 3);
	id obj = check_objc(L, 1);
	if ([obj isKindOfClass:[UIViewController class]]) {
		objc_setAssociatedObject(obj, &kNavigationBarHiddenKey,
			@(hidesNavigationBar), OBJC_ASSOCIATION_RETAIN);
		push_objc(L, obj, "uiviewcontroller");
		return 1;
	}
	if (![obj isKindOfClass:[UIView class]]) {
		luaL_typeerror(L, 1, "uiview or uiviewcontroller");
	}
	UIView *view = (UIView *)obj;
	LuaHostingController *vc =
		[[LuaHostingController alloc] initWithLuaView:view];
	objc_setAssociatedObject(vc, &kNavigationBarHiddenKey,
		@(hidesNavigationBar), OBJC_ASSOCIATION_RETAIN);
	if (lua_isfunction(L, 2))
		vc.disappearCallback = lua_reg_create(L, 2, YES);
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
