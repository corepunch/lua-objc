#import "SceneDelegate.h"
#import "LuaHost.h"

@implementation SceneDelegate
- (void)scene:(UIScene *)scene
	willConnectToSession:(UISceneSession *)session
	options:(UISceneConnectionOptions *)connectionOptions
{
	(void)session;
	(void)connectionOptions;
	if (![scene isKindOfClass:[UIWindowScene class]]) return;
	self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
	self.window.backgroundColor = UIColor.systemBackgroundColor;
	[[LuaHost shared] startWithWindow:self.window];
	[self.window makeKeyAndVisible];
}
@end
