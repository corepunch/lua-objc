#import <QuartzCore/QuartzCore.h>
#include "../shared/mesh_gradient.m"

@class LuaMeshGradientView;
@interface LuaMeshGradientTicker : NSObject
@property(nonatomic, weak) LuaMeshGradientView *view;
- (void)tick:(CADisplayLink *)link;
@end

@interface LuaMeshGradientView : UIView
@property(nonatomic) NSInteger meshWidth;
@property(nonatomic) NSInteger meshHeight;
@property(nonatomic) BOOL animated;
@property(nonatomic) LuaMeshNode *nodes;
@property(nonatomic, strong) CADisplayLink *displayLink;
- (void)tick:(CADisplayLink *)link;
- (void)replaceNodes:(LuaMeshNode *)nodes width:(NSInteger)width height:(NSInteger)height;
@end

@implementation LuaMeshGradientTicker
- (void)tick:(CADisplayLink *)link { [self.view tick:link]; }
@end

@implementation LuaMeshGradientView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.contentMode = UIViewContentModeRedraw;
		self.opaque = YES;
		_meshWidth = 3;
		_meshHeight = 3;
		_nodes = malloc(sizeof(kMeshGradientDefaultNodes));
		if (_nodes) memcpy(_nodes, kMeshGradientDefaultNodes, sizeof(kMeshGradientDefaultNodes));
	}
	return self;
}
- (void)dealloc {
	[_displayLink invalidate];
	free(_nodes);
}
- (void)setAnimated:(BOOL)animated {
	if (_animated == animated) return;
	_animated = animated;
	[_displayLink invalidate];
	_displayLink = nil;
	if (animated) {
		LuaMeshGradientTicker *ticker = [[LuaMeshGradientTicker alloc] init];
		ticker.view = self;
		_displayLink = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
		[_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	} else {
		[self setNeedsDisplay];
	}
}
- (void)tick:(CADisplayLink *)link {
	(void)link;
	mesh_gradient_animate_points(_nodes, (int)_meshWidth, (int)_meshHeight,
		[NSDate date].timeIntervalSince1970);
	[self setNeedsDisplay];
}
- (void)replaceNodes:(LuaMeshNode *)nodes width:(NSInteger)width height:(NSInteger)height {
	free(_nodes);
	_nodes = nodes;
	_meshWidth = width;
	_meshHeight = height;
	[self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
	(void)rect;
	CGRect bounds = self.bounds;
	int width = (int)MAX(8, bounds.size.width / 2);
	int height = (int)MAX(8, bounds.size.height / 2);
	CGImageRef image = mesh_gradient_image(_nodes, (int)_meshWidth, (int)_meshHeight,
		width, height);
	if (!image) return;
	[[UIImage imageWithCGImage:image] drawInRect:bounds];
	CGImageRelease(image);
}
@end

static int bridge_UIKitControls_meshGradient(lua_State *L) {
	LuaMeshGradientView *view = [[LuaMeshGradientView alloc] initWithFrame:CGRectZero];
	view.meshWidth = (NSInteger)luaL_optinteger(L, 1, 3);
	view.meshHeight = (NSInteger)luaL_optinteger(L, 2, 3);
	push_objc(L, view, "uiview");
	return 1;
}

static int bridge_UIKitControls_meshGradientConfigure(lua_State *L) {
	LuaMeshGradientView *view = (LuaMeshGradientView *)check_view(L, 1);
	int width = (int)luaL_optinteger(L, 2, view.meshWidth);
	int height = (int)luaL_optinteger(L, 3, view.meshHeight);
	if (width < 2 || height < 2) return luaL_error(L, "MeshGradient width and height must be >= 2");
	LuaMeshNode *nodes = mesh_gradient_nodes_from_lua(L, width, height, 4, 5);
	[view replaceNodes:nodes width:width height:height];
	if (lua_isboolean(L, 6)) view.animated = lua_toboolean(L, 6);
	return 0;
}

static int bridge_UIKitControls_meshGradientSample(lua_State *L) {
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
