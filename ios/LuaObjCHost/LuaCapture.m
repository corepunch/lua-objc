#import "LuaObjCHost.h"

NSData *lua_objc_capture_view_png(UIView *view) {
	if (!view || view.bounds.size.width <= 0 || view.bounds.size.height <= 0) {
		return nil;
	}

	UIGraphicsImageRendererFormat *format =
		[UIGraphicsImageRendererFormat preferredFormat];
	format.scale = view.window.screen.scale > 0 ? view.window.screen.scale : 1.0;
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
