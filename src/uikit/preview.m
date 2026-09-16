#pragma mark - Embedded controller viewport

// A controller boundary keeps navigation and compact traits scoped to the preview.
@interface LuaPreviewView : UIView
@property(nonatomic, strong) UIViewController *content;
@end
@implementation LuaPreviewView
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
	[self addSubview:_content.view];
	[_content didMoveToParentViewController:parent];
	[self setNeedsLayout];
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self attachContent]; }
- (void)layoutSubviews {
	[super layoutSubviews];
	[self attachContent];
	CGFloat scale = MIN(self.bounds.size.width / kPreviewWidth, self.bounds.size.height / kPreviewHeight);
	_content.view.bounds = CGRectMake(0, 0, kPreviewWidth, kPreviewHeight);
	_content.view.transform = CGAffineTransformMakeScale(MAX(0, scale), MAX(0, scale));
	_content.view.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
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
