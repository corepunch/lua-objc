#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include "../shared/mesh_gradient.m"

@interface LuaMeshGradientView : NSView
@property(nonatomic) NSInteger meshWidth;
@property(nonatomic) NSInteger meshHeight;
@property(nonatomic) BOOL animated;
@property(nonatomic) LuaMeshNode *nodes;
@property(nonatomic) NSInteger nodeCount;
@property(nonatomic, strong) CADisplayLink *displayLink;
@end

@implementation LuaMeshGradientView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		_meshWidth = 3;
		_meshHeight = 3;
		_nodeCount = 9;
		_nodes = malloc(sizeof(LuaMeshNode) * 9);
		memcpy(_nodes, kMeshGradientDefaultNodes, sizeof(kMeshGradientDefaultNodes));
	}
	return self;
}
- (void)dealloc {
	[_displayLink invalidate];
	free(_nodes);
}
- (BOOL)isFlipped { return YES; }
- (void)setAnimated:(BOOL)animated {
	if (_animated == animated) return;
	_animated = animated;
	[_displayLink invalidate];
	_displayLink = nil;
	if (animated) {
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	} else {
		[self setNeedsDisplay:YES];
	}
}
- (void)tick:(CADisplayLink *)link {
	(void)link;
	mesh_gradient_animate_points(_nodes, (int)_meshWidth, (int)_meshHeight,
		[NSDate date].timeIntervalSince1970);
	[self setNeedsDisplay:YES];
}
- (void)replaceNodes:(LuaMeshNode *)nodes count:(NSInteger)count width:(NSInteger)width height:(NSInteger)height {
	free(_nodes);
	_nodes = nodes;
	_nodeCount = count;
	_meshWidth = width;
	_meshHeight = height;
	[self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirty {
	(void)dirty;
	NSRect bounds = self.bounds;
	int w = (int)MAX(8, bounds.size.width / 2);
	int h = (int)MAX(8, bounds.size.height / 2);
	CGImageRef image = mesh_gradient_image(_nodes, (int)_meshWidth, (int)_meshHeight, w, h);
	if (!image) return;
	CGContextRef ctx = [NSGraphicsContext currentContext].CGContext;
	CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, 0, bounds.size.height);
	CGContextScaleCTM(ctx, 1, -1);
	CGContextDrawImage(ctx, bounds, image);
	CGContextRestoreGState(ctx);
	CGImageRelease(image);
}
@end

static int bridge_AppKitControls_meshGradient(lua_State *L) {
	LuaMeshGradientView *view = [[LuaMeshGradientView alloc] initWithFrame:NSZeroRect];
	view.meshWidth = (NSInteger)luaL_optinteger(L, 1, 3);
	view.meshHeight = (NSInteger)luaL_optinteger(L, 2, 3);
	push_objc(L, view, "nsview");
	return 1;
}

static int bridge_AppKitControls_meshGradientConfigure(lua_State *L) {
	LuaMeshGradientView *view = (LuaMeshGradientView *)check_view(L, 1);
	int width = (int)luaL_optinteger(L, 2, view.meshWidth);
	int height = (int)luaL_optinteger(L, 3, view.meshHeight);
	if (width < 2 || height < 2) return luaL_error(L, "MeshGradient width and height must be >= 2");
	int expected = width * height;
	LuaMeshNode *nodes = malloc(sizeof(LuaMeshNode) * expected);
	memcpy(nodes, kMeshGradientDefaultNodes, sizeof(LuaMeshNode) * ((expected < 9) ? expected : 9));
	if (expected > 9) {
		for (int i = 9; i < expected; i++) nodes[i] = nodes[i % 9];
	}
	if (lua_istable(L, 4)) {
		for (int i = 0; i < expected; i++) {
			lua_rawgeti(L, 4, i + 1);
			if (lua_istable(L, -1)) {
				lua_rawgeti(L, -1, 1);
				lua_rawgeti(L, -2, 2);
				nodes[i].x = (float)luaL_optnumber(L, -2, nodes[i].x);
				nodes[i].y = (float)luaL_optnumber(L, -1, nodes[i].y);
				lua_pop(L, 2);
			}
			lua_pop(L, 1);
		}
	}
	if (lua_istable(L, 5)) {
		for (int i = 0; i < expected; i++) {
			lua_rawgeti(L, 5, i + 1);
			if (lua_istable(L, -1)) {
				lua_getfield(L, -1, "red");
				lua_getfield(L, -2, "green");
				lua_getfield(L, -3, "blue");
				lua_getfield(L, -4, "alpha");
				nodes[i].r = (float)luaL_optnumber(L, -4, nodes[i].r);
				nodes[i].g = (float)luaL_optnumber(L, -3, nodes[i].g);
				nodes[i].b = (float)luaL_optnumber(L, -2, nodes[i].b);
				nodes[i].a = (float)luaL_optnumber(L, -1, 1);
				lua_pop(L, 4);
			}
			lua_pop(L, 1);
		}
	}
	[view replaceNodes:nodes count:expected width:width height:height];
	if (lua_isboolean(L, 6)) view.animated = lua_toboolean(L, 6);
	return 0;
}

static int bridge_AppKitControls_meshGradientSample(lua_State *L) {
	LuaMeshGradientView *view = (LuaMeshGradientView *)check_view(L, 1);
	float r, g, b, a;
	mesh_gradient_sample(view.nodes, (int)view.meshWidth, (int)view.meshHeight,
		(float)luaL_checknumber(L, 2), (float)luaL_checknumber(L, 3), &r, &g, &b, &a);
	lua_pushnumber(L, r);
	lua_pushnumber(L, g);
	lua_pushnumber(L, b);
	lua_pushnumber(L, a);
	return 4;
}
