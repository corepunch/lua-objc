#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/* Renders the live view hierarchy without using Simulator or Screen Recording. */
NSData * _Nullable lua_objc_capture_view_png(UIView *view);

NS_ASSUME_NONNULL_END
