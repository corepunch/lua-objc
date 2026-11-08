#pragma mark - Embedded controller viewport

/* SwiftUI `tabViewBottomAccessory`: iOS 26 floats the accessory in its own
 * Liquid Glass capsule above the tab bar, and moves it inline beside the
 * minimized bar while content scrolls. UIKit sizes the capsule, so the host
 * lays out the Lua content whenever the system changes that size. */
@interface LuaTabAccessoryHost : UIView
@property(nonatomic, strong) UIView *luaContent;
@end
@implementation LuaTabAccessoryHost
- (void)layoutSubviews {
	[super layoutSubviews];
	self.luaContent.frame = self.bounds;
	layout_recursive(self.luaContent, self.bounds.size.width);
}
@end

// A controller boundary keeps navigation and compact traits scoped to the preview.
// On the iPad the preview is a scaled phone with a bezel and phone traits; on a
// phone (`fullScreen`) the content fills the view and the device supplies the
// traits, so the app runs as it will ship.
@interface LuaPreviewView : UIView
@property(nonatomic, strong) UIViewController *content;
@property(nonatomic) CGFloat zoom;
@property(nonatomic) BOOL fullScreen;
@property(nonatomic, copy) NSString *appearance;
@property(nonatomic, strong) UIView *deviceBody;
@property(nonatomic, strong) UIView *screen;
/* The host's bottom accessory (Lua content). It joins the content's own tab
 * bar as a UITabAccessory when the content is a tab bar controller, and
 * floats on glass above the content otherwise, the way Music keeps its
 * player over any screen. */
@property(nonatomic, strong) UIView *accessory;
@property(nonatomic, strong) LuaTabAccessoryHost *accessoryHost;
@property(nonatomic, strong) UITabAccessory *tabAccessory;
@property(nonatomic, strong) UIVisualEffectView *floatingAccessory;
- (void)updateTrim;
@end
@implementation LuaPreviewView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_zoom = 1;
		// This is device artwork requested for the preview, not a replacement
		// for a UIKit control. The embedded controller remains fully interactive.
		_deviceBody = [UIView new];
		_deviceBody.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
			return traits.userInterfaceStyle == UIUserInterfaceStyleDark
				? [UIColor colorWithWhite:kPreviewDarkBodyWhite alpha:1] : UIColor.blackColor;
		}];
		_deviceBody.layer.cornerRadius = kPreviewScreenRadius + kPreviewBezel;
		_deviceBody.layer.cornerCurve = kCACornerCurveContinuous;
		_deviceBody.layer.borderWidth = kPreviewTrimWidth;
		[self addSubview:_deviceBody];
		[self updateTrim];
		// A layer colour does not follow the appearance on its own.
		[self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
			withHandler:^(LuaPreviewView *view, __unused UITraitCollection *previous) { [view updateTrim]; }];
		_screen = [UIView new];
		_screen.clipsToBounds = YES;
		_screen.layer.cornerRadius = kPreviewScreenRadius;
		_screen.layer.cornerCurve = kCACornerCurveContinuous;
		[_deviceBody addSubview:_screen];
	}
	return self;
}
- (void)updateTrim {
	_deviceBody.layer.borderColor = [UIColor.systemGrayColor resolvedColorWithTraitCollection:self.traitCollection].CGColor;
}
- (UIViewController *)parentController {
	UIResponder *responder = self.nextResponder;
	while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
	return (UIViewController *)responder;
}
- (void)setZoom:(CGFloat)zoom { _zoom = MAX(0, MIN(1, zoom)); [self setNeedsLayout]; }
- (void)setAppearance:(NSString *)appearance {
	_appearance = [appearance copy];
	self.screen.overrideUserInterfaceStyle = [appearance isEqualToString:@"dark"] ? UIUserInterfaceStyleDark
		: [appearance isEqualToString:@"light"] ? UIUserInterfaceStyleLight : UIUserInterfaceStyleUnspecified;
}
- (UIView *)contentHost { return _fullScreen ? self : _screen; }
- (void)setFullScreen:(BOOL)fullScreen {
	_fullScreen = fullScreen;
	_deviceBody.hidden = fullScreen;
	self.backgroundColor = fullScreen ? UIColor.clearColor : UIColor.secondarySystemBackgroundColor;
	if (_content.view.superview) {
		[_content.view removeFromSuperview];
		[self.contentHost addSubview:_content.view];
	}
	[self setNeedsLayout];
}
- (void)setContent:(UIViewController *)content {
	[self uninstallAccessory];
	[_content willMoveToParentViewController:nil];
	[_content.view removeFromSuperview];
	[_content removeFromParentViewController];
	_content = content;
	if (!_fullScreen) {
		_content.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
		_content.traitOverrides.userInterfaceIdiom = UIUserInterfaceIdiomPhone;
	}
	[self attachContent];
	[self installAccessory];
}
- (void)attachContent {
	UIViewController *parent = [self parentController];
	if (!_content || !parent || _content.parentViewController) return;
	[parent addChildViewController:_content];
	[self.contentHost addSubview:_content.view];
	[_content didMoveToParentViewController:parent];
	[self setNeedsLayout];
}
- (void)setAccessory:(UIView *)accessory {
	[self uninstallAccessory];
	_accessory = accessory;
	_accessoryHost = nil;
	if (accessory) {
		_accessoryHost = [[LuaTabAccessoryHost alloc] initWithFrame:CGRectZero];
		_accessoryHost.luaContent = accessory;
		[_accessoryHost addSubview:accessory];
	}
	[self installAccessory];
}
- (void)uninstallAccessory {
	if ([_content isKindOfClass:UITabBarController.class] && _tabAccessory
			&& ((UITabBarController *)_content).bottomAccessory == _tabAccessory)
		((UITabBarController *)_content).bottomAccessory = nil;
	_tabAccessory = nil;
	if (_floatingAccessory) {
		_content.additionalSafeAreaInsets = UIEdgeInsetsZero;
		[_floatingAccessory removeFromSuperview];
		_floatingAccessory = nil;
	}
	[_accessoryHost removeFromSuperview];
}
- (void)installAccessory {
	if (!_accessoryHost || !_content) return;
	if ([_content isKindOfClass:UITabBarController.class]) {
		_tabAccessory = [[UITabAccessory alloc] initWithContentView:_accessoryHost];
		((UITabBarController *)_content).bottomAccessory = _tabAccessory;
		return;
	}
	UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
	effect.interactive = YES;
	UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
	glass.cornerConfiguration = UICornerConfiguration.capsuleConfiguration;
	_accessoryHost.frame = glass.contentView.bounds;
	_accessoryHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[glass.contentView addSubview:_accessoryHost];
	_floatingAccessory = glass;
	[self addSubview:glass];
	[self setNeedsLayout];
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self attachContent]; }
- (void)layoutSubviews {
	[super layoutSubviews];
	[self attachContent];
	if (_fullScreen) {
		_content.view.frame = self.bounds;
		if (_floatingAccessory) {
			CGFloat margin = kPreviewAccessoryMargin;
			CGFloat bottom = self.bounds.size.height - MAX(self.safeAreaInsets.bottom, margin);
			_floatingAccessory.frame = CGRectMake(margin, bottom - kPreviewAccessoryHeight,
				self.bounds.size.width - 2 * margin, kPreviewAccessoryHeight);
			[self bringSubviewToFront:_floatingAccessory];
			/* The content keeps clear of the capsule, as it keeps clear of a tab bar. */
			_content.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, kPreviewAccessoryHeight + margin, 0);
		}
		[_content.view setNeedsLayout];
		[_content.view layoutIfNeeded];
		return;
	}
	CGSize bodySize = CGSizeMake(kPreviewWidth + 2 * kPreviewBezel, kPreviewHeight + 2 * kPreviewBezel);
	CGFloat scale = MAX(0, MIN((self.bounds.size.width - 2 * kPreviewMargin) / bodySize.width,
		(self.bounds.size.height - 2 * kPreviewMargin) / bodySize.height));
	scale *= self.zoom;
	self.deviceBody.bounds = (CGRect){CGPointZero, bodySize};
	self.deviceBody.transform = CGAffineTransformMakeScale(scale, scale);
	self.deviceBody.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
	self.screen.frame = CGRectMake(kPreviewBezel, kPreviewBezel, kPreviewWidth, kPreviewHeight);
	_content.view.frame = self.screen.bounds;
	[_content.view setNeedsLayout];
	[_content.view layoutIfNeeded];
}
@end
static int bridge_preview(lua_State *L) {
	LuaPreviewView *view = [LuaPreviewView new];
	view.clipsToBounds = YES;
	view.backgroundColor = UIColor.secondarySystemBackgroundColor;
	push_objc(L, view, "uiview");
	return 1;
}
