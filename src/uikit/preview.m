#pragma mark - Embedded controller viewport

// A controller boundary keeps navigation and compact traits scoped to the preview.
@interface LuaPreviewView : UIView
@property(nonatomic, strong) UIViewController *content;
@property(nonatomic, strong) UIView *deviceBody;
@property(nonatomic, strong) UIView *screen;
@end
@implementation LuaPreviewView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		// This is device artwork requested for the preview, not a replacement
		// for a UIKit control. The embedded controller remains fully interactive.
		_deviceBody = [UIView new];
		_deviceBody.backgroundColor = UIColor.blackColor;
		_deviceBody.layer.cornerRadius = kPreviewScreenRadius + kPreviewBezel;
		_deviceBody.layer.cornerCurve = kCACornerCurveContinuous;
		_deviceBody.layer.borderWidth = kPreviewTrimWidth;
		_deviceBody.layer.borderColor = UIColor.systemGrayColor.CGColor;
		[self addSubview:_deviceBody];
		_screen = [UIView new];
		_screen.clipsToBounds = YES;
		_screen.layer.cornerRadius = kPreviewScreenRadius;
		_screen.layer.cornerCurve = kCACornerCurveContinuous;
		[_deviceBody addSubview:_screen];
	}
	return self;
}
- (UIViewController *)parentController {
	UIResponder *responder = self.nextResponder;
	while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
	return (UIViewController *)responder;
}
- (void)setContent:(UIViewController *)content {
	[_content willMoveToParentViewController:nil];
	[_content.view removeFromSuperview];
	[_content removeFromParentViewController];
	_content = content;
	_content.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
	_content.traitOverrides.userInterfaceIdiom = UIUserInterfaceIdiomPhone;
	[self attachContent];
}
- (void)attachContent {
	UIViewController *parent = [self parentController];
	if (!_content || !parent || _content.parentViewController) return;
	[parent addChildViewController:_content];
	[self.screen addSubview:_content.view];
	[_content didMoveToParentViewController:parent];
	[self setNeedsLayout];
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self attachContent]; }
- (void)layoutSubviews {
	[super layoutSubviews];
	[self attachContent];
	CGSize bodySize = CGSizeMake(kPreviewWidth + 2 * kPreviewBezel, kPreviewHeight + 2 * kPreviewBezel);
	CGFloat scale = MAX(0, MIN((self.bounds.size.width - 2 * kPreviewMargin) / bodySize.width,
		(self.bounds.size.height - 2 * kPreviewMargin) / bodySize.height));
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
