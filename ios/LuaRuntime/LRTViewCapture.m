#import "LuaRuntime.h"

NSData *LRTCaptureViewPNG(UIView *view) {
	if (!view || view.bounds.size.width <= 0 || view.bounds.size.height <= 0) {
		return nil;
	}

	UIGraphicsImageRendererFormat *format =
		[UIGraphicsImageRendererFormat preferredFormat];
	// A UIWindow has no containing window; its own screen supplies the scale.
	UIWindow *window = [view isKindOfClass:UIWindow.class] ? (UIWindow *)view : view.window;
	format.scale = window.screen.scale > 0 ? window.screen.scale : 1.0;
	format.opaque = YES;
	UIGraphicsImageRenderer *renderer =
		[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
	UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		BOOL drawn = [view drawViewHierarchyInRect:view.bounds
										 afterScreenUpdates:YES];
		if (!drawn) {
			[view.layer renderInContext:context.CGContext];
		}
	}];
	return UIImagePNGRepresentation(image);
}
