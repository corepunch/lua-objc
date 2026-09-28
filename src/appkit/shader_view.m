#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

/* ShaderView: a full-bleed Metal picture, SwiftUI's
 * `TimelineView(.animation) { Rectangle().colorEffect(ShaderLibrary...) }`
 * grown into a small renderer. The app supplies Metal source; the runtime
 * prepends the shared inputs and a full-screen vertex stage, then draws every
 * display frame. Lua drives the picture by assigning `values`, a float array
 * every stage reads as `inputs.values`. Lua's timers are not the display's
 * clock, so `inputs.age` gives the seconds since `values` last changed: a
 * shader sent a position and its rate extrapolates it, and motion stays
 * smooth at the display's refresh rate however irregularly Lua updates.
 *
 * On its own the view runs one fragment function over the whole view. With
 * `layers`, it first renders `draws` — meshes with their own vertex and
 * fragment functions, blending and depth — into offscreen HDR layers, and the
 * view's function finishes the picture from them: layer i is bound at
 * texture(i), mipmapped, so the finish can crossfade layers and read wide
 * blurs (bloom) from coarse mip levels without extra passes. Geometry is
 * evaluated per vertex, not per pixel, which is what lets a scene show
 * curves, planets and terrain at full resolution.
 *
 * The layer is transparent, so shader output composites over whatever sits
 * behind the view. */

static NSString *const kShaderViewPrelude =
	@"#include <metal_stdlib>\n"
	"using namespace metal;\n"
	"struct ShaderInputs { float2 size; float time; float age; uint count; float values[256]; };\n"
	"struct ShaderVertex { float4 position [[position]]; float2 uv; };\n"
	"vertex ShaderVertex fullscreenVertex(uint id [[vertex_id]]) {\n"
	"	float2 p = float2((id << 1) & 2, id & 2);\n"
	"	ShaderVertex out;\n"
	"	out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);\n"
	"	out.uv = float2(p.x, 1.0 - p.y);\n"
	"	return out;\n"
	"}\n"
	"#line 1\n";

enum {
	kShaderViewMaxValues = 256,
	kShaderViewMaxLayers = 4,
	kShaderViewMaxParams = 64,
};
static const MTLPixelFormat kShaderLayerFormat = MTLPixelFormatRGBA16Float;
static const MTLPixelFormat kShaderDepthFormat = MTLPixelFormatDepth32Float;

typedef struct {
	float size[2];
	float time;
	float age; /* seconds since Lua last assigned `values` */
	uint32_t count;
	float values[kShaderViewMaxValues];
} LuaShaderInputs;

/* One validated entry of `draws`, with its pipeline resolved. */
@interface LuaShaderDraw : NSObject
@property(nonatomic) NSUInteger layer;
@property(nonatomic) NSUInteger count;
@property(nonatomic) NSUInteger instances;
@property(nonatomic) MTLPrimitiveType primitive;
@property(nonatomic) MTLCullMode cull;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic, strong) id<MTLDepthStencilState> depth;
@property(nonatomic, strong) id<MTLBuffer> data;
@property(nonatomic, copy) NSData *params;
@end
@implementation LuaShaderDraw
@end

@class LuaShaderView;
/* The display link retains its target; a weak hop lets the view deallocate. */
@interface LuaShaderTicker : NSObject
@property(nonatomic, weak) LuaShaderView *view;
@end

@interface LuaShaderView : MTKView <MTKViewDelegate>
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLLibrary> library;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic, copy) NSArray<NSNumber *> *values;
/* Offscreen HDR layers the draws render into, 0…4. */
@property(nonatomic) NSInteger layers;
/* Mesh passes, in order: dictionaries validated into LuaShaderDraw. */
@property(nonatomic, copy) NSArray<NSDictionary *> *draws;
@property(nonatomic) CFTimeInterval startTime;
@property(nonatomic) CFTimeInterval valuesTime;
@end

@implementation LuaShaderTicker
- (void)tick:(CADisplayLink *)link { (void)link; [self.view draw]; }
@end

static NSString *shader_draw_string(NSDictionary *draw, NSString *key, NSString *fallback) {
	id value = draw[key];
	if (!value || value == [NSNull null]) {
		if (!fallback) [NSException raise:NSInvalidArgumentException format:@"a draw requires %@", key];
		return fallback;
	}
	if (![value isKindOfClass:NSString.class])
		[NSException raise:NSInvalidArgumentException format:@"draw %@ must be a string", key];
	return value;
}

static NSInteger shader_draw_integer(NSDictionary *draw, NSString *key, NSInteger fallback) {
	id value = draw[key];
	if (!value || value == [NSNull null]) return fallback;
	if (![value isKindOfClass:NSNumber.class])
		[NSException raise:NSInvalidArgumentException format:@"draw %@ must be a number", key];
	return [value integerValue];
}

static NSArray<NSNumber *> *shader_draw_floats(NSDictionary *draw, NSString *key) {
	id value = draw[key];
	if (!value || value == [NSNull null]) return nil;
	// An empty Lua table converts to an empty dictionary.
	if ([value isKindOfClass:NSDictionary.class] && [value count] == 0) return @[];
	if (![value isKindOfClass:NSArray.class])
		[NSException raise:NSInvalidArgumentException format:@"draw %@ must be an array of numbers", key];
	for (id number in value)
		if (![number isKindOfClass:NSNumber.class])
			[NSException raise:NSInvalidArgumentException format:@"draw %@ must be an array of numbers", key];
	return value;
}

static NSUInteger shader_draw_choice(NSDictionary *draw, NSString *key, NSArray<NSString *> *names) {
	NSString *name = shader_draw_string(draw, key, names.firstObject);
	NSUInteger index = [names indexOfObject:name];
	if (index == NSNotFound)
		[NSException raise:NSInvalidArgumentException format:@"draw %@ must be one of %@, not %@",
			key, [names componentsJoinedByString:@", "], name];
	return index;
}

static NSData *shader_float_data(NSArray<NSNumber *> *numbers) {
	NSMutableData *data = [NSMutableData dataWithLength:MAX(numbers.count, 1) * sizeof(float)];
	float *floats = data.mutableBytes;
	for (NSUInteger i = 0; i < numbers.count; i++) floats[i] = numbers[i].floatValue;
	return data;
}

@implementation LuaShaderView {
	LuaShaderInputs _inputs;
	NSArray<LuaShaderDraw *> *_passes;
	NSMutableDictionary<NSString *, id<MTLRenderPipelineState>> *_pipelines;
	NSMutableArray<id<MTLTexture>> *_layerTextures;
	id<MTLTexture> _depthTexture;
	NSMutableIndexSet *_clearLayers; // layers holding only their clear colour
}

- (void)dealloc { [_displayLink invalidate]; }

/* MTKView's own timer does not redraw reliably inside the lua-objc host, so
 * the view draws explicitly from a display link in the common run loop
 * modes, like MeshGradient, and keeps animating during control tracking. */
- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[_displayLink invalidate];
	_displayLink = nil;
	if (!self.window) return;
	LuaShaderTicker *ticker = [LuaShaderTicker new];
	ticker.view = self;
	_displayLink = [self displayLinkWithTarget:ticker selector:@selector(tick:)];
	[_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (BOOL)isFlipped { return YES; }

- (void)setValues:(NSArray<NSNumber *> *)values {
	_values = [values copy];
	NSUInteger count = MIN(values.count, (NSUInteger)kShaderViewMaxValues);
	for (NSUInteger i = 0; i < count; i++) _inputs.values[i] = values[i].floatValue;
	_inputs.count = (uint32_t)count;
	_valuesTime = CACurrentMediaTime();
}

- (void)setLayers:(NSInteger)layers {
	if (layers < 0 || layers > kShaderViewMaxLayers)
		[NSException raise:NSInvalidArgumentException format:@"layers must be 0…%d", kShaderViewMaxLayers];
	for (LuaShaderDraw *draw in _passes)
		if (draw.layer >= (NSUInteger)layers)
			[NSException raise:NSInvalidArgumentException format:@"a draw renders into layer %lu", draw.layer + 1];
	_layers = layers;
	_layerTextures = nil;
	_clearLayers = nil;
}

- (id<MTLRenderPipelineState>)pipelineWithVertex:(NSString *)vertexName fragment:(NSString *)fragmentName
		blend:(NSUInteger)blend {
	NSString *key = [NSString stringWithFormat:@"%@|%@|%lu", vertexName, fragmentName, blend];
	id<MTLRenderPipelineState> pipeline = _pipelines[key];
	if (pipeline) return pipeline;
	id<MTLFunction> vertex = [self.library newFunctionWithName:vertexName];
	if (vertex.functionType != MTLFunctionTypeVertex)
		[NSException raise:NSInvalidArgumentException format:@"no vertex function named %@", vertexName];
	id<MTLFunction> fragment = [self.library newFunctionWithName:fragmentName];
	if (fragment.functionType != MTLFunctionTypeFragment)
		[NSException raise:NSInvalidArgumentException format:@"no fragment function named %@", fragmentName];
	MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
	descriptor.vertexFunction = vertex;
	descriptor.fragmentFunction = fragment;
	descriptor.depthAttachmentPixelFormat = kShaderDepthFormat;
	MTLRenderPipelineColorAttachmentDescriptor *colour = descriptor.colorAttachments[0];
	colour.pixelFormat = kShaderLayerFormat;
	if (blend != 0) {
		// alpha: premultiplied "over"; add: light accumulates.
		colour.blendingEnabled = YES;
		colour.sourceRGBBlendFactor = MTLBlendFactorOne;
		colour.sourceAlphaBlendFactor = MTLBlendFactorOne;
		colour.destinationRGBBlendFactor = blend == 1 ? MTLBlendFactorOneMinusSourceAlpha : MTLBlendFactorOne;
		colour.destinationAlphaBlendFactor = blend == 1 ? MTLBlendFactorOneMinusSourceAlpha : MTLBlendFactorOne;
	}
	NSError *error = nil;
	pipeline = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];
	if (!pipeline)
		[NSException raise:NSInvalidArgumentException format:@"%@ + %@: %@", vertexName, fragmentName,
			error.localizedDescription];
	if (!_pipelines) _pipelines = [NSMutableDictionary dictionary];
	_pipelines[key] = pipeline;
	return pipeline;
}

- (id<MTLDepthStencilState>)depthState:(NSUInteger)mode {
	MTLDepthStencilDescriptor *descriptor = [MTLDepthStencilDescriptor new];
	descriptor.depthCompareFunction = mode == 0 ? MTLCompareFunctionAlways : MTLCompareFunctionLessEqual;
	descriptor.depthWriteEnabled = mode == 2;
	return [self.device newDepthStencilStateWithDescriptor:descriptor];
}

/* Validates every draw and resolves its pipeline before any is kept, so a
 * bad list raises and leaves the previous picture running. */
- (void)setDraws:(NSArray<NSDictionary *> *)draws {
	if ([draws isKindOfClass:NSDictionary.class] && [(NSDictionary *)draws count] == 0) draws = @[];
	if (draws && ![draws isKindOfClass:NSArray.class])
		[NSException raise:NSInvalidArgumentException format:@"draws must be an array of draw tables"];
	static NSArray<NSString *> *primitives, *blends, *depths, *culls;
	static MTLPrimitiveType primitiveTypes[] = {MTLPrimitiveTypeTriangle, MTLPrimitiveTypeTriangleStrip,
		MTLPrimitiveTypeLine, MTLPrimitiveTypeLineStrip, MTLPrimitiveTypePoint};
	static MTLCullMode cullModes[] = {MTLCullModeNone, MTLCullModeBack, MTLCullModeFront};
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		primitives = @[@"triangle", @"triangleStrip", @"line", @"lineStrip", @"point"];
		blends = @[@"opaque", @"alpha", @"add"];
		depths = @[@"none", @"test", @"write"];
		culls = @[@"none", @"back", @"front"];
	});
	NSMutableArray<LuaShaderDraw *> *passes = [NSMutableArray array];
	id<MTLDepthStencilState> states[3] = {nil, nil, nil};
	for (id entry in draws) {
		if (![entry isKindOfClass:NSDictionary.class])
			[NSException raise:NSInvalidArgumentException format:@"each draw must be a table"];
		NSDictionary *draw = entry;
		LuaShaderDraw *pass = [LuaShaderDraw new];
		NSInteger layer = shader_draw_integer(draw, @"layer", 1);
		if (layer < 1 || layer > self.layers)
			[NSException raise:NSInvalidArgumentException format:@"draw layer %ld is outside the view's %ld layers",
				(long)layer, (long)self.layers];
		pass.layer = (NSUInteger)(layer - 1);
		NSArray<NSNumber *> *data = shader_draw_floats(draw, @"data");
		NSArray<NSNumber *> *params = shader_draw_floats(draw, @"params");
		if (params.count > kShaderViewMaxParams)
			[NSException raise:NSInvalidArgumentException format:@"a draw takes at most %d params", kShaderViewMaxParams];
		NSInteger count = shader_draw_integer(draw, @"count", 0);
		NSInteger instances = shader_draw_integer(draw, @"instances", 1);
		if (count <= 0) [NSException raise:NSInvalidArgumentException format:@"a draw requires a positive count"];
		if (instances <= 0) [NSException raise:NSInvalidArgumentException format:@"draw instances must be positive"];
		pass.count = (NSUInteger)count;
		pass.instances = (NSUInteger)instances;
		pass.primitive = primitiveTypes[shader_draw_choice(draw, @"primitive", primitives)];
		pass.cull = cullModes[shader_draw_choice(draw, @"cull", culls)];
		NSUInteger depth = shader_draw_choice(draw, @"depth", depths);
		if (!states[depth]) states[depth] = [self depthState:depth];
		pass.depth = states[depth];
		pass.pipeline = [self pipelineWithVertex:shader_draw_string(draw, @"vertex", nil)
			fragment:shader_draw_string(draw, @"fragment", nil) blend:shader_draw_choice(draw, @"blend", blends)];
		NSData *bytes = shader_float_data(data ?: @[]);
		pass.data = [self.device newBufferWithBytes:bytes.bytes length:bytes.length
			options:MTLResourceStorageModeShared];
		pass.params = shader_float_data(params ?: @[]);
		[passes addObject:pass];
	}
	_draws = [draws copy] ?: @[];
	_passes = passes;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
	(void)view; (void)size;
}

/* Layers follow the target's pixel size; they are rebuilt when it changes. */
- (void)prepareLayersWidth:(NSUInteger)width height:(NSUInteger)height {
	id<MTLTexture> first = _layerTextures.firstObject;
	if (first && first.width == width && first.height == height && _layerTextures.count == (NSUInteger)self.layers)
		return;
	_layerTextures = [NSMutableArray array];
	_clearLayers = [NSMutableIndexSet indexSet];
	MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:kShaderLayerFormat
		width:width height:height mipmapped:YES];
	descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	descriptor.storageMode = MTLStorageModePrivate;
	for (NSInteger i = 0; i < self.layers; i++) [_layerTextures addObject:[self.device newTextureWithDescriptor:descriptor]];
	MTLTextureDescriptor *depth = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:kShaderDepthFormat
		width:width height:height mipmapped:NO];
	depth.usage = MTLTextureUsageRenderTarget;
	depth.storageMode = MTLStorageModePrivate;
	_depthTexture = [self.device newTextureWithDescriptor:depth];
}

/* Encodes one frame: each layer's draws, the layers' mip chains, then the
 * finishing function into `pass`. A layer that no draw uses is cleared once,
 * so the finish never samples stale or uninitialised memory, and then left
 * alone. */
- (void)encodeFrame:(id<MTLCommandBuffer>)buffer pass:(MTLRenderPassDescriptor *)finishPass
		width:(NSUInteger)width height:(NSUInteger)height {
	LuaShaderInputs inputs = _inputs;
	inputs.size[0] = (float)width;
	inputs.size[1] = (float)height;
	CFTimeInterval now = CACurrentMediaTime();
	inputs.time = (float)(now - self.startTime);
	inputs.age = self.valuesTime > 0 ? (float)(now - self.valuesTime) : 0.0f;
	if (self.layers > 0) {
		[self prepareLayersWidth:width height:height];
		for (NSUInteger layer = 0; layer < _layerTextures.count; layer++) {
			BOOL used = NO;
			for (LuaShaderDraw *draw in _passes) used = used || draw.layer == layer;
			if (!used && [_clearLayers containsIndex:layer]) continue;
			MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
			pass.colorAttachments[0].texture = _layerTextures[layer];
			pass.colorAttachments[0].loadAction = MTLLoadActionClear;
			pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
			pass.colorAttachments[0].storeAction = MTLStoreActionStore;
			pass.depthAttachment.texture = _depthTexture;
			pass.depthAttachment.loadAction = MTLLoadActionClear;
			pass.depthAttachment.clearDepth = 1.0;
			pass.depthAttachment.storeAction = MTLStoreActionDontCare;
			id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
			[encoder setVertexBytes:&inputs length:sizeof(inputs) atIndex:0];
			[encoder setFragmentBytes:&inputs length:sizeof(inputs) atIndex:0];
			for (LuaShaderDraw *draw in _passes) {
				if (draw.layer != layer) continue;
				[encoder setRenderPipelineState:draw.pipeline];
				[encoder setDepthStencilState:draw.depth];
				[encoder setCullMode:draw.cull];
				[encoder setVertexBuffer:draw.data offset:0 atIndex:1];
				[encoder setFragmentBuffer:draw.data offset:0 atIndex:1];
				[encoder setVertexBytes:draw.params.bytes length:draw.params.length atIndex:2];
				[encoder setFragmentBytes:draw.params.bytes length:draw.params.length atIndex:2];
				[encoder drawPrimitives:draw.primitive vertexStart:0 vertexCount:draw.count instanceCount:draw.instances];
			}
			[encoder endEncoding];
			if (used) [_clearLayers removeIndex:layer];
			else [_clearLayers addIndex:layer];
		}
		id<MTLBlitCommandEncoder> blit = [buffer blitCommandEncoder];
		for (id<MTLTexture> texture in _layerTextures) [blit generateMipmapsForTexture:texture];
		[blit endEncoding];
	}
	id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:finishPass];
	[encoder setRenderPipelineState:self.pipeline];
	[encoder setFragmentBytes:&inputs length:sizeof(inputs) atIndex:0];
	for (NSUInteger layer = 0; layer < _layerTextures.count; layer++)
		[encoder setFragmentTexture:_layerTextures[layer] atIndex:layer];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
	[encoder endEncoding];
}

- (void)drawInMTKView:(MTKView *)view {
	MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
	id<CAMetalDrawable> drawable = view.currentDrawable;
	if (!pass || !drawable || !self.pipeline) return;
	id<MTLCommandBuffer> buffer = [self.queue commandBuffer];
	[self encodeFrame:buffer pass:pass width:(NSUInteger)view.drawableSize.width
		height:(NSUInteger)view.drawableSize.height];
	[buffer presentDrawable:drawable];
	[buffer commit];
}

/* Draws one frame offscreen at a pixel size with the current values and
 * draws and waits for it; returns the target and the GPU time in ms. */
- (id<MTLTexture>)renderOffscreenWidth:(NSUInteger)width height:(NSUInteger)height milliseconds:(double *)ms {
	MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:self.colorPixelFormat
		width:width height:height mipmapped:NO];
	descriptor.usage = MTLTextureUsageRenderTarget;
	descriptor.storageMode = MTLStorageModeShared;
	id<MTLTexture> target = [self.device newTextureWithDescriptor:descriptor];
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = target;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	id<MTLCommandBuffer> buffer = [self.queue commandBuffer];
	[self encodeFrame:buffer pass:pass width:width height:height];
	[buffer commit];
	[buffer waitUntilCompleted];
	if (ms) *ms = (buffer.GPUEndTime - buffer.GPUStartTime) * 1000.0;
	return target;
}
@end

/* _shaderView(source, functionName) -> view, or raises the compiler error. */
static int bridge_AppKitControls_shaderView(lua_State *L) {
	NSString *source = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
	NSString *function = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	if (!device) return luaL_error(L, "ShaderView: Metal is unavailable");
	NSError *error = nil;
	id<MTLLibrary> library = [device newLibraryWithSource:[kShaderViewPrelude stringByAppendingString:source]
		options:nil error:&error];
	if (!library) return luaL_error(L, "ShaderView: %s", error.localizedDescription.UTF8String);
	id<MTLFunction> fragment = [library newFunctionWithName:function];
	if (!fragment) return luaL_error(L, "ShaderView: no fragment function named %s", function.UTF8String);

	MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
	descriptor.vertexFunction = [library newFunctionWithName:@"fullscreenVertex"];
	descriptor.fragmentFunction = fragment;
	descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
	if (!pipeline) return luaL_error(L, "ShaderView: %s", error.localizedDescription.UTF8String);

	LuaShaderView *view = [[LuaShaderView alloc] initWithFrame:NSZeroRect device:device];
	view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
	view.clearColor = MTLClearColorMake(0, 0, 0, 0);
	view.layer.opaque = NO;
	view.queue = [device newCommandQueue];
	view.library = library;
	view.pipeline = pipeline;
	view.startTime = CACurrentMediaTime();
	view.delegate = view;
	view.paused = YES;
	view.enableSetNeedsDisplay = NO;
	push_objc(L, view, "nsview");
	return 1;
}

static LuaShaderView *check_shader_view(lua_State *L, lua_Integer *width, lua_Integer *height) {
	NSView *view = check_view(L, 1);
	if (![view isKindOfClass:[LuaShaderView class]]) luaL_argerror(L, 1, "ShaderView expected");
	*width = luaL_checkinteger(L, 2);
	*height = luaL_checkinteger(L, 3);
	luaL_argcheck(L, *width > 0, 2, "width must be positive");
	luaL_argcheck(L, *height > 0, 3, "height must be positive");
	return (LuaShaderView *)view;
}

/* _shaderFrameTime(view, width, height) -> milliseconds of GPU time for one
 * frame at that pixel size, draws included; the regression hook for
 * expensive scenes. */
static int bridge_AppKitControls_shaderFrameTime(lua_State *L) {
	lua_Integer width, height;
	LuaShaderView *view = check_shader_view(L, &width, &height);
	double ms = 0;
	[view renderOffscreenWidth:(NSUInteger)width height:(NSUInteger)height milliseconds:&ms];
	lua_pushnumber(L, ms);
	return 1;
}

/* _shaderPixel(view, width, height, x, y) -> r, g, b, a in 0…1 at pixel
 * (x, y) from the top-left of one offscreen frame; lets tests check what the
 * draws and the finishing pass actually produce. */
static int bridge_AppKitControls_shaderPixel(lua_State *L) {
	lua_Integer width, height;
	LuaShaderView *view = check_shader_view(L, &width, &height);
	lua_Integer x = luaL_checkinteger(L, 4), y = luaL_checkinteger(L, 5);
	luaL_argcheck(L, x >= 0 && x < width, 4, "x is outside the frame");
	luaL_argcheck(L, y >= 0 && y < height, 5, "y is outside the frame");
	id<MTLTexture> target = [view renderOffscreenWidth:(NSUInteger)width height:(NSUInteger)height milliseconds:NULL];
	uint8_t bgra[4];
	[target getBytes:bgra bytesPerRow:4 fromRegion:MTLRegionMake2D((NSUInteger)x, (NSUInteger)y, 1, 1) mipmapLevel:0];
	lua_pushnumber(L, bgra[2] / 255.0);
	lua_pushnumber(L, bgra[1] / 255.0);
	lua_pushnumber(L, bgra[0] / 255.0);
	lua_pushnumber(L, bgra[3] / 255.0);
	return 4;
}
