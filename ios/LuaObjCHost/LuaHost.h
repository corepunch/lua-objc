#import <UIKit/UIKit.h>

@interface LuaHost : NSObject
+ (instancetype)shared;
- (void)startWithWindow:(UIWindow *)window;
- (void)captureInternalScreenshotIfRequested;
@end

UIWindow *lua_objc_host_window(void);
