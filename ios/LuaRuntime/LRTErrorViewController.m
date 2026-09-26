#import "LuaRuntime.h"

/* The host's status screen uses the system empty-state presentation: native
 * typography, symbols, colors and appearance, a spinner while waiting, and
 * actions instead of a wall of text. Raw details stay one tap away. */
@implementation LRTErrorViewController {
	UIContentUnavailableConfiguration *_configuration;
}

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message
	details:(NSString *)details retry:(void (^)(void))retry {
	self = [super initWithNibName:nil bundle:nil];
	UIContentUnavailableConfiguration *config = [UIContentUnavailableConfiguration emptyConfiguration];
	config.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
	config.text = title;
	config.secondaryText = message;
	if (retry) {
		UIButtonConfiguration *button = [UIButtonConfiguration borderedProminentButtonConfiguration];
		button.title = @"Try Again";
		config.button = button;
		config.buttonProperties.primaryAction = [UIAction actionWithHandler:^(UIAction *action) {
			retry();
		}];
	}
	if (details.length) {
		UIButtonConfiguration *copy = [UIButtonConfiguration plainButtonConfiguration];
		copy.title = @"Copy Details";
		config.secondaryButton = copy;
		NSString *text = [details copy];
		config.secondaryButtonProperties.primaryAction = [UIAction actionWithHandler:^(UIAction *action) {
			UIPasteboard.generalPasteboard.string = text;
		}];
	}
	_configuration = config;
	return self;
}

- (instancetype)initWaitingForPackager:(NSString *)url {
	self = [super initWithNibName:nil bundle:nil];
	UIContentUnavailableConfiguration *config = [UIContentUnavailableConfiguration loadingConfiguration];
	config.text = @"Waiting for Packager";
	config.secondaryText = [NSString stringWithFormat:
		@"Start the packager on your Mac with make ios-run PROJECT=<app>. "
		@"This screen continues on its own when %@ responds.", url];
	_configuration = config;
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.contentUnavailableConfiguration = _configuration;
}

@end
