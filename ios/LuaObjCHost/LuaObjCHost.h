#ifndef LUA_OBJC_HOST_H
#define LUA_OBJC_HOST_H

#import <UIKit/UIKit.h>

// Shared declarations for the host's independently compiled implementations.
// Implementation-only state and helpers stay in their owning .m file.

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@end

@interface LuaHost : NSObject
+ (instancetype)shared;
- (void)startWithWindow:(UIWindow *)window;
- (void)captureInternalScreenshotIfRequested;
@end

UIWindow * _Nullable lua_objc_host_window(void);

@interface LuaSourceLoader : NSObject
@property (nonatomic, copy, nullable) NSURL *baseURL;
+ (instancetype)shared;
- (BOOL)ping:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)dataForPath:(NSString *)rel error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)sourceForModule:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)entryPath:(NSError * _Nullable * _Nullable)error;
- (void)dropCacheForPath:(NSString *)rel;
@end

typedef void (^LuaHotHandler)(NSDictionary *event);

@interface LuaHotClient : NSObject
@property (nonatomic, copy, nullable) LuaHotHandler handler;
- (void)connectToURL:(NSURL *)url;
- (void)disconnect;
@end

@interface LuaErrorOverlay : UIViewController
- (instancetype)initWithMessage:(NSString *)message;
@end

/* Renders the live view hierarchy without using Simulator or Screen Recording. */
NSData * _Nullable lua_objc_capture_view_png(UIView *view);
NS_ASSUME_NONNULL_END

#endif
