#import "LuaRuntime.h"

@implementation LRTErrorViewController {
	NSString *_message;
}

- (instancetype)initWithMessage:(NSString *)message {
	self = [super initWithNibName:nil bundle:nil];
	_message = [message copy];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor colorWithRed:0.72 green:0.11
		blue:0.11 alpha:1];
	UITextView *text = [[UITextView alloc] initWithFrame:self.view.bounds];
	text.autoresizingMask = UIViewAutoresizingFlexibleWidth
		| UIViewAutoresizingFlexibleHeight;
	text.editable = NO;
	text.backgroundColor = UIColor.clearColor;
	text.textColor = UIColor.whiteColor;
	text.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	text.text = _message;
	text.textContainerInset = UIEdgeInsetsMake(48, 16, 16, 16);
	[self.view addSubview:text];
}
@end
