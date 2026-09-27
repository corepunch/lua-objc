// Offscreen drawing, image and movie services for the Reel package.
//
// A standalone Lua module (like StorageScan): it never touches the AppKit
// bridge, keeps no Lua callbacks, and holds only plain CoreGraphics state.
// Reels render time-based frames offline, so nothing here uses Core
// Animation or the display clock; the Lua side decides what each frame
// contains and this module turns it into pixels, stills and H.264.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <lua.h>
#import <lauxlib.h>

static const char *ImageMetatable = "ReelNative.Image";
static const char *CanvasMetatable = "ReelNative.Canvas";
static const char *PathMetatable = "ReelNative.Path";
static const char *TextMetatable = "ReelNative.Text";
static const char *AccumulatorMetatable = "ReelNative.Accumulator";
static const char *MovieMetatable = "ReelNative.Movie";

// SF Symbols are rasterised as masks at sizes on a 15 % ladder, so a chip
// that grows on a spring reuses a handful of cached masks instead of one per
// frame, while staying sharp at every size it passes through.
static const double SymbolSizeStep = 1.15;
static const double SymbolPointRatio = 0.8;
static const double MinimumSymbolPixels = 8;
static const double MovieKeyFrameInterval = 1; // seconds
static const useconds_t MovieBackpressureSleep = 2000;

static CGColorSpaceRef reel_srgb(void) {
	static CGColorSpaceRef space;
	if (!space) space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	return space;
}

// Every canvas and derived image uses the pixel layout of a 32BGRA
// CVPixelBuffer, so a finished frame copies straight into the encoder.
static const CGBitmapInfo ReelBitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;

static CGContextRef reel_bitmap(size_t width, size_t height, void *data, size_t bytesPerRow) {
	return CGBitmapContextCreate(data, width, height, 8, bytesPerRow, reel_srgb(), ReelBitmapInfo);
}

static CGColorRef reel_color(lua_State *L, int index) {
	double r = luaL_checknumber(L, index), g = luaL_checknumber(L, index + 1);
	double b = luaL_checknumber(L, index + 2), a = luaL_optnumber(L, index + 3, 1);
	CGFloat components[4] = {r, g, b, a};
	return CGColorCreate(reel_srgb(), components);
}

#pragma mark - Image

// An image keeps its pixels and the scale that maps its points to them:
// window captures are 2x, so crops and placement stay in window points.
typedef struct { CGImageRef image; double scale; } ReelImage;

static ReelImage *reel_check_image(lua_State *L, int index) {
	ReelImage *image = luaL_checkudata(L, index, ImageMetatable);
	if (!image->image) luaL_error(L, "image is released");
	return image;
}

static void reel_push_image(lua_State *L, CGImageRef cgImage, double scale) {
	ReelImage *image = lua_newuserdatauv(L, sizeof(ReelImage), 0);
	image->image = cgImage;
	image->scale = scale;
	luaL_setmetatable(L, ImageMetatable);
}

// Redraws an image into an owned bitmap so its pixels can be read or edited.
static CGContextRef reel_image_bitmap(CGImageRef image) {
	size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
	CGContextRef context = reel_bitmap(width, height, NULL, width * 4);
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
	return context;
}

// image(path, scale): loads any ImageIO format; `scale` is pixels per point.
static int reel_image(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	double scale = luaL_optnumber(L, 2, 1);
	NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
	CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
	CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
	if (source) CFRelease(source);
	if (!image) return luaL_error(L, "cannot read image %s", path);
	reel_push_image(L, image, scale);
	return 1;
}

static int reel_image_size(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	lua_pushnumber(L, CGImageGetWidth(image->image) / image->scale);
	lua_pushnumber(L, CGImageGetHeight(image->image) / image->scale);
	return 2;
}

static int reel_image_pixel_size(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	lua_pushinteger(L, (lua_Integer)CGImageGetWidth(image->image));
	lua_pushinteger(L, (lua_Integer)CGImageGetHeight(image->image));
	return 2;
}

// crop(x, y, w, h): a piece in points, origin top-left.
static int reel_image_crop(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	double s = image->scale;
	CGRect rect = CGRectIntegral(CGRectMake(luaL_checknumber(L, 2) * s, luaL_checknumber(L, 3) * s,
		luaL_checknumber(L, 4) * s, luaL_checknumber(L, 5) * s));
	CGImageRef cropped = CGImageCreateWithImageInRect(image->image, rect);
	if (!cropped) return luaL_error(L, "crop is outside the image");
	reel_push_image(L, cropped, s);
	return 1;
}

// pixel(x, y) -> r, g, b, a (0...1) at a point, origin top-left.
static int reel_image_pixel(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	CGRect rect = CGRectMake(floor(luaL_checknumber(L, 2) * image->scale),
		floor(luaL_checknumber(L, 3) * image->scale), 1, 1);
	CGImageRef one = CGImageCreateWithImageInRect(image->image, rect);
	if (!one) return luaL_error(L, "pixel is outside the image");
	uint8_t bgra[4] = {0};
	CGContextRef context = reel_bitmap(1, 1, bgra, 4);
	CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), one);
	CGContextRelease(context);
	CGImageRelease(one);
	double alpha = bgra[3] / 255.0;
	double unpremultiply = alpha > 0 ? 1 / alpha : 0;
	lua_pushnumber(L, bgra[2] / 255.0 * unpremultiply);
	lua_pushnumber(L, bgra[1] / 255.0 * unpremultiply);
	lua_pushnumber(L, bgra[0] / 255.0 * unpremultiply);
	lua_pushnumber(L, alpha);
	return 4;
}

// keyed(r, g, b, tolerance, softness): makes pixels near the colour clear,
// so a chart cut from a page floats on the stage by itself. Distances are
// the largest channel difference, in 0...1.
static int reel_image_keyed(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	double r = luaL_checknumber(L, 2) * 255, g = luaL_checknumber(L, 3) * 255, b = luaL_checknumber(L, 4) * 255;
	double tolerance = luaL_optnumber(L, 5, 7.0 / 255) * 255;
	double softness = fmax(1e-6, luaL_optnumber(L, 6, 14.0 / 255) * 255);
	CGContextRef context = reel_image_bitmap(image->image);
	uint8_t *p = CGBitmapContextGetData(context);
	size_t count = CGBitmapContextGetWidth(context) * CGBitmapContextGetHeight(context);
	for (size_t i = 0; i < count; i++, p += 4) {
		double d = fmax(fabs(p[2] - r), fmax(fabs(p[1] - g), fabs(p[0] - b)));
		double a = fmin(1, fmax(0, (d - tolerance) / softness));
		for (int c = 0; c < 4; c++) p[c] = (uint8_t)(p[c] * a);
	}
	reel_push_image(L, CGBitmapContextCreateImage(context), image->scale);
	CGContextRelease(context);
	return 1;
}

// downsampled(factor): fewer pixels, same size in points, for sprites that
// only ever appear small (a wall of windows).
static int reel_image_downsampled(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	double factor = luaL_checknumber(L, 2);
	size_t width = MAX(1, (size_t)(CGImageGetWidth(image->image) * factor));
	size_t height = MAX(1, (size_t)(CGImageGetHeight(image->image) * factor));
	CGContextRef context = reel_bitmap(width, height, NULL, width * 4);
	CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image->image);
	reel_push_image(L, CGBitmapContextCreateImage(context), image->scale * factor);
	CGContextRelease(context);
	return 1;
}

// opaqueBounds(threshold) -> x, y, w, h in pixels (top-left) of the pixels
// whose alpha exceeds `threshold` (0...1); nil when there are none. A
// `--screenshot` includes the window shadow, and this finds the window.
static int reel_image_opaque_bounds(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	uint8_t threshold = (uint8_t)(luaL_optnumber(L, 2, 250.0 / 255) * 255);
	CGContextRef context = reel_image_bitmap(image->image);
	const uint8_t *p = CGBitmapContextGetData(context);
	size_t width = CGBitmapContextGetWidth(context), height = CGBitmapContextGetHeight(context);
	size_t minX = width, minY = height, maxX = 0, maxY = 0;
	// Bitmap memory is top row first, so these are top-left pixel coordinates.
	for (size_t y = 0; y < height; y++) {
		for (size_t x = 0; x < width; x++) {
			if (p[(y * width + x) * 4 + 3] <= threshold) continue;
			minX = MIN(minX, x); maxX = MAX(maxX, x);
			minY = MIN(minY, y); maxY = MAX(maxY, y);
		}
	}
	CGContextRelease(context);
	if (minX > maxX) { lua_pushnil(L); return 1; }
	lua_pushinteger(L, (lua_Integer)minX);
	lua_pushinteger(L, (lua_Integer)minY);
	lua_pushinteger(L, (lua_Integer)(maxX - minX + 1));
	lua_pushinteger(L, (lua_Integer)(maxY - minY + 1));
	return 4;
}

// cropPixels(x, y, w, h, scale): a piece in pixels, carrying a new scale.
static int reel_image_crop_pixels(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	CGRect rect = CGRectMake(luaL_checknumber(L, 2), luaL_checknumber(L, 3),
		luaL_checknumber(L, 4), luaL_checknumber(L, 5));
	CGImageRef cropped = CGImageCreateWithImageInRect(image->image, rect);
	if (!cropped) return luaL_error(L, "crop is outside the image");
	reel_push_image(L, cropped, luaL_optnumber(L, 6, image->scale));
	return 1;
}

// flattened(r, g, b): an opaque copy over a solid colour.
static int reel_image_flattened(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	CGColorRef color = reel_color(L, 2);
	size_t width = CGImageGetWidth(image->image), height = CGImageGetHeight(image->image);
	CGContextRef context = reel_bitmap(width, height, NULL, width * 4);
	CGContextSetFillColorWithColor(context, color);
	CGContextFillRect(context, CGRectMake(0, 0, width, height));
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image->image);
	CGColorRelease(color);
	reel_push_image(L, CGBitmapContextCreateImage(context), image->scale);
	CGContextRelease(context);
	return 1;
}

static BOOL reel_write_image(CGImageRef image, const char *path, CFStringRef type, NSDictionary *options) {
	NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
	CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
	if (!destination) return NO;
	CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)options);
	BOOL ok = CGImageDestinationFinalize(destination);
	CFRelease(destination);
	return ok;
}

static int reel_image_write(lua_State *L) {
	ReelImage *image = reel_check_image(L, 1);
	const char *path = luaL_checkstring(L, 2);
	BOOL jpeg = strcasestr(path, ".jpg") || strcasestr(path, ".jpeg");
	NSDictionary *options = jpeg
		? @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(luaL_optnumber(L, 3, 0.82))} : @{};
	CFStringRef type = (__bridge CFStringRef)(jpeg ? UTTypeJPEG : UTTypePNG).identifier;
	if (!reel_write_image(image->image, path, type, options)) return luaL_error(L, "cannot write %s", path);
	return 0;
}

static int reel_image_gc(lua_State *L) {
	ReelImage *image = luaL_checkudata(L, 1, ImageMetatable);
	if (image->image) CGImageRelease(image->image);
	image->image = NULL;
	return 0;
}

#pragma mark - Path

typedef struct { CGMutablePathRef path; } ReelPath;

static CGMutablePathRef reel_check_path(lua_State *L, int index) {
	return ((ReelPath *)luaL_checkudata(L, index, PathMetatable))->path;
}

static int reel_path(lua_State *L) {
	ReelPath *path = lua_newuserdatauv(L, sizeof(ReelPath), 0);
	path->path = CGPathCreateMutable();
	luaL_setmetatable(L, PathMetatable);
	return 1;
}

#define REEL_ARG(i) luaL_checknumber(L, (i))

static int reel_path_move(lua_State *L) { CGPathMoveToPoint(reel_check_path(L, 1), NULL, REEL_ARG(2), REEL_ARG(3)); lua_settop(L, 1); return 1; }
static int reel_path_line(lua_State *L) { CGPathAddLineToPoint(reel_check_path(L, 1), NULL, REEL_ARG(2), REEL_ARG(3)); lua_settop(L, 1); return 1; }
static int reel_path_curve(lua_State *L) {
	CGPathAddCurveToPoint(reel_check_path(L, 1), NULL, REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5), REEL_ARG(6), REEL_ARG(7));
	lua_settop(L, 1); return 1;
}
static int reel_path_close(lua_State *L) { CGPathCloseSubpath(reel_check_path(L, 1)); lua_settop(L, 1); return 1; }
static int reel_path_rect(lua_State *L) {
	CGPathAddRect(reel_check_path(L, 1), NULL, CGRectMake(REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5)));
	lua_settop(L, 1); return 1;
}
static int reel_path_rounded(lua_State *L) {
	CGRect rect = CGRectMake(REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5));
	double radius = fmin(luaL_checknumber(L, 6), fmin(rect.size.width, rect.size.height) / 2);
	if (radius > 0 && rect.size.width > 0 && rect.size.height > 0)
		CGPathAddRoundedRect(reel_check_path(L, 1), NULL, rect, radius, radius);
	else
		CGPathAddRect(reel_check_path(L, 1), NULL, rect);
	lua_settop(L, 1); return 1;
}
static int reel_path_ellipse(lua_State *L) {
	CGPathAddEllipseInRect(reel_check_path(L, 1), NULL, CGRectMake(REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5)));
	lua_settop(L, 1); return 1;
}
// arc(cx, cy, r, from, to, clockwise): angles in radians, y down.
static int reel_path_arc(lua_State *L) {
	CGPathAddArc(reel_check_path(L, 1), NULL, REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5), REEL_ARG(6), lua_toboolean(L, 7));
	lua_settop(L, 1); return 1;
}

static int reel_path_gc(lua_State *L) {
	ReelPath *path = luaL_checkudata(L, 1, PathMetatable);
	if (path->path) CGPathRelease(path->path);
	path->path = NULL;
	return 0;
}

#pragma mark - Text

// Text is drawn from glyph outlines, so it scales, clips and takes gradient
// fills like any other shape and never snaps to a pixel grid mid-motion.
typedef struct { CGPathRef path; double width, ascent, descent; } ReelText;

static NSFontWeight reel_weight(const char *name) {
	if (!name) return NSFontWeightRegular;
	if (!strcmp(name, "ultraLight")) return NSFontWeightUltraLight;
	if (!strcmp(name, "thin")) return NSFontWeightThin;
	if (!strcmp(name, "light")) return NSFontWeightLight;
	if (!strcmp(name, "medium")) return NSFontWeightMedium;
	if (!strcmp(name, "semibold")) return NSFontWeightSemibold;
	if (!strcmp(name, "bold")) return NSFontWeightBold;
	if (!strcmp(name, "heavy")) return NSFontWeightHeavy;
	if (!strcmp(name, "black")) return NSFontWeightBlack;
	return NSFontWeightRegular;
}

// text(string, size, weight, kern, monospacedDigits)
static int reel_text(lua_State *L) {
	NSString *string = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	double size = luaL_checknumber(L, 2);
	NSFontWeight weight = reel_weight(luaL_optstring(L, 3, "regular"));
	double kern = luaL_optnumber(L, 4, 0);
	NSFont *font = lua_toboolean(L, 5)
		? [NSFont monospacedDigitSystemFontOfSize:size weight:weight]
		: [NSFont systemFontOfSize:size weight:weight];
	NSMutableDictionary *attributes = [@{NSFontAttributeName: font} mutableCopy];
	if (kern != 0) attributes[NSKernAttributeName] = @(kern);
	CTLineRef line = CTLineCreateWithAttributedString(
		(__bridge CFAttributedStringRef)[[NSAttributedString alloc] initWithString:string attributes:attributes]);
	CGMutablePathRef path = CGPathCreateMutable();
	for (id object in (__bridge NSArray *)CTLineGetGlyphRuns(line)) {
		CTRunRef run = (__bridge CTRunRef)object;
		CTFontRef runFont = (__bridge CTFontRef)((__bridge NSDictionary *)CTRunGetAttributes(run))[(__bridge NSString *)kCTFontAttributeName];
		CFIndex count = CTRunGetGlyphCount(run);
		CGGlyph *glyphs = malloc(sizeof(CGGlyph) * MAX(1, count));
		CGPoint *positions = malloc(sizeof(CGPoint) * MAX(1, count));
		CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs);
		CTRunGetPositions(run, CFRangeMake(0, 0), positions);
		for (CFIndex i = 0; i < count; i++) {
			// Glyph outlines are y-up; flip them so the path is y-down with its
			// origin on the baseline, like everything else on a canvas.
			CGAffineTransform place = CGAffineTransformMake(1, 0, 0, -1, positions[i].x, -positions[i].y);
			CGPathRef glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], &place);
			if (glyph) { CGPathAddPath(path, NULL, glyph); CGPathRelease(glyph); }
		}
		free(glyphs);
		free(positions);
	}
	CGFloat ascent = 0, descent = 0;
	double width = CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
	CFRelease(line);
	ReelText *text = lua_newuserdatauv(L, sizeof(ReelText), 0);
	*text = (ReelText){path, width, ascent, descent};
	luaL_setmetatable(L, TextMetatable);
	return 1;
}

static ReelText *reel_check_text(lua_State *L, int index) {
	return luaL_checkudata(L, index, TextMetatable);
}

// metrics() -> width, ascent, descent
static int reel_text_metrics(lua_State *L) {
	ReelText *text = reel_check_text(L, 1);
	lua_pushnumber(L, text->width);
	lua_pushnumber(L, text->ascent);
	lua_pushnumber(L, text->descent);
	return 3;
}

static int reel_text_gc(lua_State *L) {
	ReelText *text = luaL_checkudata(L, 1, TextMetatable);
	if (text->path) CGPathRelease(text->path);
	text->path = NULL;
	return 0;
}

#pragma mark - Canvas

typedef struct { CGContextRef context; size_t width, height; } ReelCanvas;

static ReelCanvas *reel_check_canvas(lua_State *L, int index) {
	ReelCanvas *canvas = luaL_checkudata(L, index, CanvasMetatable);
	if (!canvas->context) luaL_error(L, "canvas is released");
	return canvas;
}
#define REEL_CONTEXT(L) (reel_check_canvas((L), 1)->context)

// canvas(width, height): pixels, origin top-left, y down.
static int reel_canvas(lua_State *L) {
	lua_Integer width = luaL_checkinteger(L, 1), height = luaL_checkinteger(L, 2);
	luaL_argcheck(L, width > 0 && height > 0, 1, "canvas needs a positive size");
	CGContextRef context = reel_bitmap((size_t)width, (size_t)height, NULL, (size_t)width * 4);
	if (!context) return luaL_error(L, "cannot create a %dx%d canvas", (int)width, (int)height);
	CGContextTranslateCTM(context, 0, height);
	CGContextScaleCTM(context, 1, -1);
	CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
	ReelCanvas *canvas = lua_newuserdatauv(L, sizeof(ReelCanvas), 0);
	*canvas = (ReelCanvas){context, (size_t)width, (size_t)height};
	luaL_setmetatable(L, CanvasMetatable);
	return 1;
}

static int reel_canvas_size(lua_State *L) {
	ReelCanvas *canvas = reel_check_canvas(L, 1);
	lua_pushinteger(L, (lua_Integer)canvas->width);
	lua_pushinteger(L, (lua_Integer)canvas->height);
	return 2;
}

// clear(r, g, b, a): replaces every pixel, ignoring the clip and transform.
static int reel_canvas_clear(lua_State *L) {
	ReelCanvas *canvas = reel_check_canvas(L, 1);
	CGColorRef color = reel_color(L, 2);
	CGContextSaveGState(canvas->context);
	CGContextResetClip(canvas->context);
	CGContextSetBlendMode(canvas->context, kCGBlendModeCopy);
	CGContextSetFillColorWithColor(canvas->context, color);
	CGContextFillRect(canvas->context, CGRectMake(0, 0, canvas->width, canvas->height));
	CGContextRestoreGState(canvas->context);
	CGColorRelease(color);
	return 0;
}

static int reel_canvas_save(lua_State *L) { CGContextSaveGState(REEL_CONTEXT(L)); return 0; }
static int reel_canvas_restore(lua_State *L) { CGContextRestoreGState(REEL_CONTEXT(L)); return 0; }
static int reel_canvas_translate(lua_State *L) { CGContextTranslateCTM(REEL_CONTEXT(L), REEL_ARG(2), REEL_ARG(3)); return 0; }
static int reel_canvas_scale(lua_State *L) {
	double sx = luaL_checknumber(L, 2);
	CGContextScaleCTM(REEL_CONTEXT(L), sx, luaL_optnumber(L, 3, sx));
	return 0;
}
static int reel_canvas_rotate(lua_State *L) { CGContextRotateCTM(REEL_CONTEXT(L), REEL_ARG(2)); return 0; }
static int reel_canvas_alpha(lua_State *L) { CGContextSetAlpha(REEL_CONTEXT(L), REEL_ARG(2)); return 0; }

// shadow(dx, dy, blur, r, g, b, a) in canvas pixels (unaffected by the
// transform, as in CoreGraphics); shadow() removes it.
static int reel_canvas_shadow(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	if (lua_isnoneornil(L, 2)) { CGContextSetShadowWithColor(context, CGSizeZero, 0, NULL); return 0; }
	CGColorRef color = reel_color(L, 5);
	// The canvas is flipped; a positive dy should still move the shadow down.
	CGContextSetShadowWithColor(context, CGSizeMake(REEL_ARG(2), -REEL_ARG(3)), REEL_ARG(4), color);
	CGColorRelease(color);
	return 0;
}

// fill(path, r, g, b, a, evenOdd)
static int reel_canvas_fill(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	CGMutablePathRef path = reel_check_path(L, 2);
	CGColorRef color = reel_color(L, 3);
	CGContextAddPath(context, path);
	CGContextSetFillColorWithColor(context, color);
	if (lua_toboolean(L, 7)) CGContextEOFillPath(context); else CGContextFillPath(context);
	CGColorRelease(color);
	return 0;
}

// stroke(path, width, r, g, b, a)
static int reel_canvas_stroke(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	CGMutablePathRef path = reel_check_path(L, 2);
	CGContextSetLineWidth(context, luaL_checknumber(L, 3));
	CGColorRef color = reel_color(L, 4);
	CGContextAddPath(context, path);
	CGContextSetStrokeColorWithColor(context, color);
	CGContextStrokePath(context);
	CGColorRelease(color);
	return 0;
}

// clip(path, evenOdd)
static int reel_canvas_clip(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	CGContextAddPath(context, reel_check_path(L, 2));
	if (lua_toboolean(L, 3)) CGContextEOClip(context); else CGContextClip(context);
	return 0;
}

static int reel_canvas_clip_rect(lua_State *L) {
	CGContextClipToRect(REEL_CONTEXT(L), CGRectMake(REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5)));
	return 0;
}

static int reel_canvas_fill_rect(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	CGColorRef color = reel_color(L, 6);
	CGContextSetFillColorWithColor(context, color);
	CGContextFillRect(context, CGRectMake(REEL_ARG(2), REEL_ARG(3), REEL_ARG(4), REEL_ARG(5)));
	CGColorRelease(color);
	return 0;
}

// Gradient stops are a flat list: r, g, b, a, location, r, g, b, a, location…
static CGGradientRef reel_gradient(lua_State *L, int index) {
	luaL_checktype(L, index, LUA_TTABLE);
	lua_Integer n = luaL_len(L, index);
	luaL_argcheck(L, n >= 10 && n % 5 == 0, index, "gradient needs at least two r, g, b, a, location stops");
	size_t count = (size_t)n / 5;
	CGFloat *components = malloc(sizeof(CGFloat) * count * 4);
	CGFloat *locations = malloc(sizeof(CGFloat) * count);
	for (size_t i = 0; i < count; i++) {
		for (int c = 0; c < 5; c++) {
			lua_geti(L, index, (lua_Integer)(i * 5 + c + 1));
			CGFloat value = lua_tonumber(L, -1);
			lua_pop(L, 1);
			if (c < 4) components[i * 4 + c] = value; else locations[i] = value;
		}
	}
	CGGradientRef gradient = CGGradientCreateWithColorComponents(reel_srgb(), components, locations, count);
	free(components);
	free(locations);
	return gradient;
}

static CGGradientDrawingOptions reel_extend(lua_State *L, int before, int after) {
	return (lua_toboolean(L, before) ? kCGGradientDrawsBeforeStartLocation : 0)
		| (lua_toboolean(L, after) ? kCGGradientDrawsAfterEndLocation : 0);
}

// linearGradient(stops, x0, y0, x1, y1, extendBefore, extendAfter): fills the clip.
static int reel_canvas_linear(lua_State *L) {
	CGGradientRef gradient = reel_gradient(L, 2);
	CGContextDrawLinearGradient(REEL_CONTEXT(L), gradient, CGPointMake(REEL_ARG(3), REEL_ARG(4)),
		CGPointMake(REEL_ARG(5), REEL_ARG(6)), reel_extend(L, 7, 8));
	CGGradientRelease(gradient);
	return 0;
}

// radialGradient(stops, cx, cy, r0, r1, extendBefore, extendAfter)
static int reel_canvas_radial(lua_State *L) {
	CGGradientRef gradient = reel_gradient(L, 2);
	CGPoint center = CGPointMake(REEL_ARG(3), REEL_ARG(4));
	CGContextDrawRadialGradient(REEL_CONTEXT(L), gradient, center, REEL_ARG(5), center, REEL_ARG(6), reel_extend(L, 7, 8));
	CGGradientRelease(gradient);
	return 0;
}

// image(image, x, y, w, h): upright, top-left at (x, y).
static int reel_canvas_image(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	ReelImage *image = reel_check_image(L, 2);
	double x = luaL_checknumber(L, 3), y = luaL_checknumber(L, 4);
	double w = luaL_checknumber(L, 5), h = luaL_checknumber(L, 6);
	CGContextSaveGState(context);
	CGContextTranslateCTM(context, x, y + h);
	CGContextScaleCTM(context, 1, -1);
	CGContextDrawImage(context, CGRectMake(0, 0, w, h), image->image);
	CGContextRestoreGState(context);
	return 0;
}

// fillText(text, x, baseline, r, g, b, a)
static int reel_canvas_fill_text(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	ReelText *text = reel_check_text(L, 2);
	CGColorRef color = reel_color(L, 5);
	CGContextSaveGState(context);
	CGContextTranslateCTM(context, luaL_checknumber(L, 3), luaL_checknumber(L, 4));
	CGContextAddPath(context, text->path);
	CGContextSetFillColorWithColor(context, color);
	CGContextFillPath(context);
	CGContextRestoreGState(context);
	CGColorRelease(color);
	return 0;
}

// clipText(text, x, baseline): clips to the glyphs, for gradient fills.
static int reel_canvas_clip_text(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	ReelText *text = reel_check_text(L, 2);
	CGAffineTransform place = CGAffineTransformMakeTranslation(luaL_checknumber(L, 3), luaL_checknumber(L, 4));
	CGPathRef placed = CGPathCreateCopyByTransformingPath(text->path, &place);
	CGContextAddPath(context, placed);
	CGContextClip(context);
	CGPathRelease(placed);
	return 0;
}

static NSMutableDictionary<NSString *, id> *reel_symbol_cache(void) {
	static NSMutableDictionary *cache;
	if (!cache) cache = [NSMutableDictionary dictionary];
	return cache;
}

// Rasterises an SF Symbol's alpha into a grey mask `pixels` tall.
static CGImageRef reel_symbol_mask(NSString *name, size_t pixels, double *aspect) {
	NSString *key = [NSString stringWithFormat:@"%@|%zu", name, pixels];
	NSArray *cached = reel_symbol_cache()[key];
	if (cached) { *aspect = [cached[1] doubleValue]; return (__bridge CGImageRef)cached[0]; }
	NSImage *base = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
	if (!base) return NULL;
	NSImage *symbol = [base imageWithSymbolConfiguration:
		[NSImageSymbolConfiguration configurationWithPointSize:pixels * SymbolPointRatio weight:NSFontWeightSemibold]];
	double ratio = symbol.size.width / fmax(1, symbol.size.height);
	size_t width = MAX(1, (size_t)(pixels * ratio)), height = pixels;
	CGContextRef rgba = reel_bitmap(width, height, NULL, width * 4);
	[NSGraphicsContext saveGraphicsState];
	NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:rgba flipped:NO];
	[symbol drawInRect:NSMakeRect(0, 0, width, height)];
	[NSGraphicsContext restoreGraphicsState];
	CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
	CGContextRef maskContext = CGBitmapContextCreate(NULL, width, height, 8, width, gray, (CGBitmapInfo)kCGImageAlphaNone);
	CGColorSpaceRelease(gray);
	const uint8_t *src = CGBitmapContextGetData(rgba);
	uint8_t *dst = CGBitmapContextGetData(maskContext);
	for (size_t i = 0; i < width * height; i++) dst[i] = src[i * 4 + 3];
	CGImageRef mask = CGBitmapContextCreateImage(maskContext);
	CGContextRelease(maskContext);
	CGContextRelease(rgba);
	reel_symbol_cache()[key] = @[(__bridge_transfer id)mask, @(ratio)];
	*aspect = ratio;
	return (__bridge CGImageRef)reel_symbol_cache()[key][0];
}

// symbol(name, cx, cy, height, r, g, b, a) -> width drawn
static int reel_canvas_symbol(lua_State *L) {
	CGContextRef context = REEL_CONTEXT(L);
	NSString *name = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	double cx = luaL_checknumber(L, 3), cy = luaL_checknumber(L, 4), size = luaL_checknumber(L, 5);
	if (size < 1) { lua_pushnumber(L, 0); return 1; }
	CGAffineTransform ctm = CGContextGetCTM(context);
	double deviceSize = size * hypot(ctm.a, ctm.b);
	double step = pow(SymbolSizeStep, round(log(fmax(deviceSize, MinimumSymbolPixels)) / log(SymbolSizeStep)));
	double aspect = 1;
	CGImageRef mask = reel_symbol_mask(name, (size_t)fmax(MinimumSymbolPixels, step), &aspect);
	if (!mask) return luaL_error(L, "unknown SF Symbol %s", name.UTF8String);
	double w = size * aspect;
	CGColorRef color = reel_color(L, 6);
	CGContextSaveGState(context);
	CGContextTranslateCTM(context, cx - w / 2, cy + size / 2);
	CGContextScaleCTM(context, 1, -1);
	CGContextClipToMask(context, CGRectMake(0, 0, w, size), mask);
	CGContextSetFillColorWithColor(context, color);
	CGContextFillRect(context, CGRectMake(0, 0, w, size));
	CGContextRestoreGState(context);
	CGColorRelease(color);
	lua_pushnumber(L, w);
	return 1;
}

// snapshot() -> image of the canvas as it is now.
static int reel_canvas_snapshot(lua_State *L) {
	reel_push_image(L, CGBitmapContextCreateImage(REEL_CONTEXT(L)), 1);
	return 1;
}

// pixel(x, y) -> r, g, b, a (0...1) of a canvas pixel, unpremultiplied.
static int reel_canvas_pixel(lua_State *L) {
	ReelCanvas *canvas = reel_check_canvas(L, 1);
	lua_Integer x = luaL_checkinteger(L, 2), y = luaL_checkinteger(L, 3);
	luaL_argcheck(L, x >= 0 && y >= 0 && (size_t)x < canvas->width && (size_t)y < canvas->height, 2, "pixel is outside the canvas");
	const uint8_t *p = (const uint8_t *)CGBitmapContextGetData(canvas->context)
		+ (size_t)y * CGBitmapContextGetBytesPerRow(canvas->context) + (size_t)x * 4;
	double alpha = p[3] / 255.0, unpremultiply = alpha > 0 ? 1 / alpha : 0;
	lua_pushnumber(L, p[2] / 255.0 * unpremultiply);
	lua_pushnumber(L, p[1] / 255.0 * unpremultiply);
	lua_pushnumber(L, p[0] / 255.0 * unpremultiply);
	lua_pushnumber(L, alpha);
	return 4;
}

static int reel_canvas_gc(lua_State *L) {
	ReelCanvas *canvas = luaL_checkudata(L, 1, CanvasMetatable);
	if (canvas->context) CGContextRelease(canvas->context);
	canvas->context = NULL;
	return 0;
}

#pragma mark - Motion blur accumulator

// Sums several sub-frame renders per channel and writes their average: a
// real shutter instead of a smear filter, so fast motion blurs along its
// actual path and still frames stay sharp.
typedef struct { uint16_t *sum; size_t bytes; lua_Integer count; } ReelAccumulator;

static ReelAccumulator *reel_check_accumulator(lua_State *L, int index) {
	return luaL_checkudata(L, index, AccumulatorMetatable);
}

static int reel_accumulator(lua_State *L) {
	lua_Integer width = luaL_checkinteger(L, 1), height = luaL_checkinteger(L, 2);
	ReelAccumulator *accumulator = lua_newuserdatauv(L, sizeof(ReelAccumulator), 0);
	accumulator->bytes = (size_t)width * (size_t)height * 4;
	accumulator->sum = calloc(accumulator->bytes, sizeof(uint16_t));
	accumulator->count = 0;
	luaL_setmetatable(L, AccumulatorMetatable);
	return 1;
}

static void reel_accumulator_check_canvas(lua_State *L, ReelAccumulator *accumulator, ReelCanvas *canvas) {
	if (canvas->width * canvas->height * 4 != accumulator->bytes
		|| CGBitmapContextGetBytesPerRow(canvas->context) != canvas->width * 4)
		luaL_error(L, "canvas and accumulator sizes differ");
}

static int reel_accumulator_add(lua_State *L) {
	ReelAccumulator *accumulator = reel_check_accumulator(L, 1);
	ReelCanvas *canvas = reel_check_canvas(L, 2);
	reel_accumulator_check_canvas(L, accumulator, canvas);
	if (accumulator->count >= 255) return luaL_error(L, "at most 255 sub-frames per frame");
	const uint8_t *src = CGBitmapContextGetData(canvas->context);
	uint16_t *sum = accumulator->sum;
	for (size_t i = 0; i < accumulator->bytes; i++) sum[i] += src[i];
	accumulator->count++;
	return 0;
}

// resolve(canvas): writes the average into the canvas and starts over.
static int reel_accumulator_resolve(lua_State *L) {
	ReelAccumulator *accumulator = reel_check_accumulator(L, 1);
	ReelCanvas *canvas = reel_check_canvas(L, 2);
	reel_accumulator_check_canvas(L, accumulator, canvas);
	if (accumulator->count == 0) return luaL_error(L, "nothing was accumulated");
	uint8_t *dst = CGBitmapContextGetData(canvas->context);
	uint16_t n = (uint16_t)accumulator->count, half = n / 2;
	uint16_t *sum = accumulator->sum;
	for (size_t i = 0; i < accumulator->bytes; i++) { dst[i] = (uint8_t)((sum[i] + half) / n); sum[i] = 0; }
	accumulator->count = 0;
	return 0;
}

static int reel_accumulator_gc(lua_State *L) {
	ReelAccumulator *accumulator = reel_check_accumulator(L, 1);
	free(accumulator->sum);
	accumulator->sum = NULL;
	return 0;
}

#pragma mark - Movie

// H.264 in a QuickTime movie, Rec. 709 tagged, with an optional audio file
// muxed in at the end. Frames arrive from Lua one at a time.
@interface ReelMovie : NSObject
@property (nonatomic, strong) AVAssetWriter *writer;
@property (nonatomic, strong) AVAssetWriterInput *video;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property (nonatomic) int32_t fps;
@property (nonatomic) int64_t frames;
@property (nonatomic) size_t width, height;
@end
@implementation ReelMovie
@end

typedef struct { void *movie; } ReelMovieBox;

static ReelMovie *reel_check_movie(lua_State *L, int index) {
	ReelMovieBox *box = luaL_checkudata(L, index, MovieMetatable);
	if (!box->movie) luaL_error(L, "movie is finished");
	return (__bridge ReelMovie *)box->movie;
}

// movie{path, width, height, fps, bitrate}
static int reel_movie(lua_State *L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	lua_getfield(L, 1, "path"); const char *path = luaL_checkstring(L, -1); lua_pop(L, 1);
	lua_getfield(L, 1, "width"); lua_Integer width = luaL_checkinteger(L, -1); lua_pop(L, 1);
	lua_getfield(L, 1, "height"); lua_Integer height = luaL_checkinteger(L, -1); lua_pop(L, 1);
	lua_getfield(L, 1, "fps"); lua_Integer fps = luaL_optinteger(L, -1, 30); lua_pop(L, 1);
	lua_getfield(L, 1, "bitrate"); lua_Integer bitrate = luaL_optinteger(L, -1, 24000000); lua_pop(L, 1);
	NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
	[NSFileManager.defaultManager removeItemAtURL:url error:nil];
	NSError *error = nil;
	AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
	if (!writer) return luaL_error(L, "cannot write %s: %s", path, error.localizedDescription.UTF8String);
	AVAssetWriterInput *video = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
		AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(width), AVVideoHeightKey: @(height),
		AVVideoColorPropertiesKey: @{AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
			AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
			AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2},
		AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(bitrate),
			AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
			AVVideoMaxKeyFrameIntervalKey: @((NSInteger)(fps * MovieKeyFrameInterval)),
			AVVideoExpectedSourceFrameRateKey: @(fps)},
	}];
	video.expectsMediaDataInRealTime = NO;
	AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
		assetWriterInputPixelBufferAdaptorWithAssetWriterInput:video sourcePixelBufferAttributes:@{
			(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
			(NSString *)kCVPixelBufferWidthKey: @(width), (NSString *)kCVPixelBufferHeightKey: @(height)}];
	[writer addInput:video];
	if (![writer startWriting]) return luaL_error(L, "cannot start %s: %s", path, writer.error.localizedDescription.UTF8String);
	[writer startSessionAtSourceTime:kCMTimeZero];
	ReelMovie *movie = [ReelMovie new];
	movie.writer = writer; movie.video = video; movie.adaptor = adaptor;
	movie.fps = (int32_t)fps; movie.width = (size_t)width; movie.height = (size_t)height;
	ReelMovieBox *box = lua_newuserdatauv(L, sizeof(ReelMovieBox), 0);
	box->movie = (__bridge_retained void *)movie;
	luaL_setmetatable(L, MovieMetatable);
	return 1;
}

// append(canvas): the next frame.
static int reel_movie_append(lua_State *L) {
	ReelMovie *movie = reel_check_movie(L, 1);
	ReelCanvas *canvas = reel_check_canvas(L, 2);
	if (canvas->width != movie.width || canvas->height != movie.height) return luaL_error(L, "canvas and movie sizes differ");
	while (!movie.video.readyForMoreMediaData) {
		if (movie.writer.status == AVAssetWriterStatusFailed)
			return luaL_error(L, "encoding failed: %s", movie.writer.error.localizedDescription.UTF8String);
		usleep(MovieBackpressureSleep);
	}
	CVPixelBufferRef buffer = NULL;
	CVPixelBufferPoolCreatePixelBuffer(NULL, movie.adaptor.pixelBufferPool, &buffer);
	if (!buffer) return luaL_error(L, "no pixel buffer available");
	CVPixelBufferLockBaseAddress(buffer, 0);
	uint8_t *dst = CVPixelBufferGetBaseAddress(buffer);
	size_t dstRow = CVPixelBufferGetBytesPerRow(buffer);
	const uint8_t *src = CGBitmapContextGetData(canvas->context);
	size_t srcRow = CGBitmapContextGetBytesPerRow(canvas->context);
	for (size_t y = 0; y < canvas->height; y++) memcpy(dst + y * dstRow, src + y * srcRow, canvas->width * 4);
	CVPixelBufferUnlockBaseAddress(buffer, 0);
	BOOL ok = [movie.adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(movie.frames, movie.fps)];
	CVPixelBufferRelease(buffer);
	if (!ok) return luaL_error(L, "encoding failed: %s", movie.writer.error.localizedDescription.UTF8String);
	movie.frames++;
	return 0;
}

// finish(): closes the file; returns the number of frames written.
static int reel_movie_finish(lua_State *L) {
	ReelMovieBox *box = luaL_checkudata(L, 1, MovieMetatable);
	if (!box->movie) return luaL_error(L, "movie is finished");
	ReelMovie *movie = (__bridge_transfer ReelMovie *)box->movie;
	box->movie = NULL;
	[movie.video markAsFinished];
	[movie.writer endSessionAtSourceTime:CMTimeMake(movie.frames, movie.fps)];
	dispatch_semaphore_t done = dispatch_semaphore_create(0);
	[movie.writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
	dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
	if (movie.writer.status != AVAssetWriterStatusCompleted)
		return luaL_error(L, "encoding failed: %s", movie.writer.error.localizedDescription.UTF8String);
	lua_pushinteger(L, movie.frames);
	return 1;
}

static int reel_movie_gc(lua_State *L) {
	ReelMovieBox *box = luaL_checkudata(L, 1, MovieMetatable);
	if (box->movie) {
		ReelMovie *movie = (__bridge_transfer ReelMovie *)box->movie;
		box->movie = NULL;
		[movie.writer cancelWriting];
	}
	return 0;
}

#pragma mark - Module

static void reel_class(lua_State *L, const char *name, const luaL_Reg *methods, lua_CFunction gc) {
	luaL_newmetatable(L, name);
	lua_newtable(L);
	luaL_setfuncs(L, methods, 0);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, gc);
	lua_setfield(L, -2, "__gc");
	lua_pop(L, 1);
}

int luaopen_ReelNative(lua_State *L) {
	static const luaL_Reg imageMethods[] = {
		{"size", reel_image_size}, {"pixelSize", reel_image_pixel_size}, {"crop", reel_image_crop},
		{"cropPixels", reel_image_crop_pixels}, {"pixel", reel_image_pixel}, {"keyed", reel_image_keyed},
		{"downsampled", reel_image_downsampled}, {"opaqueBounds", reel_image_opaque_bounds},
		{"flattened", reel_image_flattened}, {"write", reel_image_write}, {NULL, NULL}};
	static const luaL_Reg pathMethods[] = {
		{"moveTo", reel_path_move}, {"lineTo", reel_path_line}, {"curveTo", reel_path_curve},
		{"close", reel_path_close}, {"rect", reel_path_rect}, {"roundedRect", reel_path_rounded},
		{"ellipse", reel_path_ellipse}, {"arc", reel_path_arc}, {NULL, NULL}};
	static const luaL_Reg textMethods[] = {{"metrics", reel_text_metrics}, {NULL, NULL}};
	static const luaL_Reg canvasMethods[] = {
		{"size", reel_canvas_size}, {"clear", reel_canvas_clear}, {"save", reel_canvas_save},
		{"restore", reel_canvas_restore}, {"translate", reel_canvas_translate}, {"scale", reel_canvas_scale},
		{"rotate", reel_canvas_rotate}, {"alpha", reel_canvas_alpha}, {"shadow", reel_canvas_shadow},
		{"fill", reel_canvas_fill}, {"stroke", reel_canvas_stroke}, {"clip", reel_canvas_clip},
		{"clipRect", reel_canvas_clip_rect}, {"fillRect", reel_canvas_fill_rect},
		{"linearGradient", reel_canvas_linear}, {"radialGradient", reel_canvas_radial},
		{"image", reel_canvas_image}, {"fillText", reel_canvas_fill_text}, {"clipText", reel_canvas_clip_text},
		{"symbol", reel_canvas_symbol}, {"snapshot", reel_canvas_snapshot}, {"pixel", reel_canvas_pixel},
		{NULL, NULL}};
	static const luaL_Reg accumulatorMethods[] = {{"add", reel_accumulator_add}, {"resolve", reel_accumulator_resolve}, {NULL, NULL}};
	static const luaL_Reg movieMethods[] = {{"append", reel_movie_append}, {"finish", reel_movie_finish}, {NULL, NULL}};
	reel_class(L, ImageMetatable, imageMethods, reel_image_gc);
	reel_class(L, PathMetatable, pathMethods, reel_path_gc);
	reel_class(L, TextMetatable, textMethods, reel_text_gc);
	reel_class(L, CanvasMetatable, canvasMethods, reel_canvas_gc);
	reel_class(L, AccumulatorMetatable, accumulatorMethods, reel_accumulator_gc);
	reel_class(L, MovieMetatable, movieMethods, reel_movie_gc);
	static const luaL_Reg functions[] = {
		{"image", reel_image}, {"path", reel_path}, {"text", reel_text}, {"canvas", reel_canvas},
		{"accumulator", reel_accumulator}, {"movie", reel_movie}, {NULL, NULL}};
	luaL_newlib(L, functions);
	return 1;
}
