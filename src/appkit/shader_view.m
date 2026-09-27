#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

/* ShaderView: a full-bleed Metal fragment shader, SwiftUI's
 * `TimelineView(.animation) { Rectangle().colorEffect(ShaderLibrary...) }`.
 * The app supplies Metal source defining one fragment function; the runtime
 * prepends the shared inputs and a full-screen vertex stage, then draws every
 * display frame. Lua drives the picture by assigning `values`, a float array
 * the shader reads as `inputs.values`. The layer is transparent, so shader
 * output composites over whatever sits behind the view. */

static NSString *const kShaderViewPrelude =
	@"#include <metal_stdlib>\n"
	"using namespace metal;\n"
	"struct ShaderInputs { float2 size; float time; uint count; float values[256]; };\n"
	"struct ShaderVertex { float4 position [[position]]; float2 uv; };\n"
	"vertex ShaderVertex lua_shader_vertex(uint id [[vertex_id]]) {\n"
	"	float2 p = float2((id << 1) & 2, id & 2);\n"
	"	ShaderVertex out;\n"
	"	out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);\n"
	"	out.uv = float2(p.x, 1.0 - p.y);\n"
	"	return out;\n"
	"}\n"
	"#line 1\n";

enum { kShaderViewMaxValues = 256 };

typedef struct {
	float size[2];
	float time;
	uint32_t count;
	float values[kShaderViewMaxValues];
} LuaShaderInputs;

@class LuaShaderView;
/* The display link retains its target; a weak hop lets the view deallocate. */
@interface LuaShaderTicker : NSObject
@property(nonatomic, weak) LuaShaderView *view;
@end

@interface LuaShaderView : MTKView <MTKViewDelegate>
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property(nonatomic, copy) NSArray<NSNumber *> *values;
@property(nonatomic) CFTimeInterval startTime;
@end

@implementation LuaShaderTicker
- (void)tick:(CADisplayLink *)link { (void)link; [self.view draw]; }
@end

@implementation LuaShaderView {
	LuaShaderInputs _inputs;
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
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
	(void)view; (void)size;
}

- (void)drawInMTKView:(MTKView *)view {
	MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
	id<CAMetalDrawable> drawable = view.currentDrawable;
	if (!pass || !drawable || !self.pipeline) return;
	_inputs.size[0] = (float)view.drawableSize.width;
	_inputs.size[1] = (float)view.drawableSize.height;
	_inputs.time = (float)(CACurrentMediaTime() - self.startTime);
	id<MTLCommandBuffer> buffer = [self.queue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
	[encoder setRenderPipelineState:self.pipeline];
	[encoder setFragmentBytes:&_inputs length:sizeof(_inputs) atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
	[encoder endEncoding];
	[buffer presentDrawable:drawable];
	[buffer commit];
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
	descriptor.vertexFunction = [library newFunctionWithName:@"lua_shader_vertex"];
	descriptor.fragmentFunction = fragment;
	descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
	if (!pipeline) return luaL_error(L, "ShaderView: %s", error.localizedDescription.UTF8String);

	LuaShaderView *view = [[LuaShaderView alloc] initWithFrame:NSZeroRect device:device];
	view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
	view.clearColor = MTLClearColorMake(0, 0, 0, 0);
	view.layer.opaque = NO;
	view.queue = [device newCommandQueue];
	view.pipeline = pipeline;
	view.startTime = CACurrentMediaTime();
	view.delegate = view;
	view.paused = YES;
	view.enableSetNeedsDisplay = NO;
	push_objc(L, view, "nsview");
	return 1;
}
