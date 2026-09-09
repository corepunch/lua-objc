#ifndef LUA_RUNTIME_H
#define LUA_RUNTIME_H

#import <UIKit/UIKit.h>

// Shared declarations for the host's independently compiled implementations.
// Implementation-only state and helpers stay in their owning .m file.

NS_ASSUME_NONNULL_BEGIN

@interface LRTApplicationDelegate : UIResponder <UIApplicationDelegate>
@end

@interface LRTSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@end

@interface LRTApplicationController : NSObject
+ (instancetype)shared;
- (void)startWithWindow:(UIWindow *)window;
- (void)captureInternalScreenshotIfRequested;
@end

UIWindow * _Nullable LRTApplicationWindow(void);

@interface LRTResourceLoader : NSObject
@property (nonatomic, copy, nullable) NSURL *baseURL;
+ (instancetype)shared;
- (BOOL)ping:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)dataForPath:(NSString *)rel error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)sourceForModule:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)entryPath:(NSError * _Nullable * _Nullable)error;
- (void)dropCacheForPath:(NSString *)rel;
@end

typedef void (^LRTReloadEventHandler)(NSDictionary *event);

@interface LRTReloadConnection : NSObject
@property (nonatomic, copy, nullable) LRTReloadEventHandler handler;
- (void)connectToURL:(NSURL *)url;
- (void)disconnect;
@end

@interface LRTErrorViewController : UIViewController
- (instancetype)initWithMessage:(NSString *)message;
@end

/* Renders the live view hierarchy without using Simulator or Screen Recording. */
NSData * _Nullable LRTCaptureViewPNG(UIView *view);
NS_ASSUME_NONNULL_END

#endif
