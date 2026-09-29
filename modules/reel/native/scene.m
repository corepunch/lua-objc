#pragma mark - SceneKit scenes rendered offline

/* A SceneKit scene the Lua side poses completely for every frame, rendered
 * offscreen through Metal into an Image. Included by ReelNative.m.
 *
 * Nothing here runs on a clock: no SCNAction, no implicit animation, no
 * display link, no temporal antialiasing. The reel computes every pose, the
 * camera and each dynamic texture from `t` and this module only turns that
 * description into pixels, so a still at any time and every motion-blur
 * sub-frame agree exactly with the movie.
 *
 * Nodes are addressed by integer handles; 0 is the root. Each node is two
 * SCNNodes, as in the live SceneView: the outer one carries the pose and the
 * children, an inner content node carries the model or geometry and its idle
 * motion (spin, bob), so the two never overwrite each other. Models load
 * through shared/scene_models.m, the same loader the SceneView uses. */

static const char *SceneMetatable = "ReelNative.Scene";

// Screens and texture cards are seen at steep angles; trilinear filtering
// with anisotropy keeps their text readable instead of shimmering.
static const CGFloat SceneTextureAnisotropy = 16;
static const NSUInteger SceneSampleCount = 4;

@interface ReelSceneState : NSObject
@property(nonatomic, strong) SCNScene *scene;
@property(nonatomic, strong) SCNRenderer *renderer;
@property(nonatomic, strong) NSMutableArray<SCNNode *> *nodes;     // outer node per handle
@property(nonatomic, strong) NSMutableArray<SCNNode *> *contents;  // content node per handle
@property(nonatomic, strong) id<MTLTexture> colorTexture, resolveTexture, depthTexture;
@end
@implementation ReelSceneState
@end

static id<MTLDevice> reel_metal_device(void) {
	static id<MTLDevice> device;
	if (!device) device = MTLCreateSystemDefaultDevice();
	return device;
}

static id<MTLCommandQueue> reel_metal_queue(void) {
	static id<MTLCommandQueue> queue;
	if (!queue) queue = [reel_metal_device() newCommandQueue];
	return queue;
}

typedef struct { void *state; } ReelSceneBox;

static ReelSceneState *reel_check_scene(lua_State *L, int index) {
	ReelSceneBox *box = luaL_checkudata(L, index, SceneMetatable);
	if (!box->state) luaL_error(L, "scene is released");
	return (__bridge ReelSceneState *)box->state;
}

static NSUInteger reel_scene_handle(lua_State *L, ReelSceneState *state, int index) {
	lua_Integer handle = luaL_checkinteger(L, index);
	if (handle < 0 || (NSUInteger)handle >= state.nodes.count) luaL_error(L, "no scene node %d", (int)handle);
	return (NSUInteger)handle;
}

static double reel_field(lua_State *L, int table, const char *key, double fallback) {
	lua_getfield(L, table, key);
	double value = lua_isnumber(L, -1) ? lua_tonumber(L, -1) : fallback;
	lua_pop(L, 1);
	return value;
}

static BOOL reel_field_bool(lua_State *L, int table, const char *key, BOOL fallback) {
	lua_getfield(L, table, key);
	BOOL value = lua_isnil(L, -1) ? fallback : lua_toboolean(L, -1);
	lua_pop(L, 1);
	return value;
}

static NSString *reel_field_string(lua_State *L, int table, const char *key) {
	lua_getfield(L, table, key);
	NSString *value = lua_type(L, -1) == LUA_TSTRING ? @(lua_tostring(L, -1)) : nil;
	lua_pop(L, 1);
	return value;
}

// A colour field {r, g, b, a}; nil when absent.
static NSColor *reel_field_color(lua_State *L, int table, const char *key) {
	lua_getfield(L, table, key);
	NSColor *color = nil;
	if (lua_istable(L, -1)) {
		CGFloat c[4] = {0, 0, 0, 1};
		for (int i = 0; i < 4; i++) {
			lua_geti(L, -1, i + 1);
			if (lua_isnumber(L, -1)) c[i] = lua_tonumber(L, -1);
			lua_pop(L, 1);
		}
		color = [NSColor colorWithSRGBRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
	}
	lua_pop(L, 1);
	return color;
}

// scene() -> an empty scene with no lights and no background.
static int reel_scene(lua_State *L) {
	id<MTLDevice> device = reel_metal_device();
	if (!device) return luaL_error(L, "reel: SceneKit rendering needs a Metal device");
	ReelSceneState *state = [ReelSceneState new];
	state.scene = [SCNScene scene];
	state.renderer = [SCNRenderer rendererWithDevice:device options:nil];
	state.renderer.scene = state.scene;
	state.renderer.autoenablesDefaultLighting = NO;
	state.renderer.jitteringEnabled = NO;
	state.renderer.playing = NO;
	state.nodes = [NSMutableArray arrayWithObject:state.scene.rootNode];
	state.contents = [NSMutableArray arrayWithObject:state.scene.rootNode];
	ReelSceneBox *box = lua_newuserdatauv(L, sizeof(ReelSceneBox), 0);
	box->state = (__bridge_retained void *)state;
	luaL_setmetatable(L, SceneMetatable);
	return 1;
}

// node(parent) -> handle of a new empty node under `parent` (0 = root).
static int reel_scene_node(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	NSUInteger parent = reel_scene_handle(L, state, 2);
	SCNNode *node = [SCNNode node], *content = [SCNNode node];
	[node addChildNode:content];
	[state.nodes[parent] addChildNode:node];
	[state.nodes addObject:node];
	[state.contents addObject:content];
	lua_pushinteger(L, (lua_Integer)state.nodes.count - 1);
	return 1;
}

// model(handle, path) -> true, or nil and a message.
static int reel_scene_model(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	NSUInteger handle = reel_scene_handle(L, state, 2);
	NSString *error = nil;
	SCNNode *model = scene_model(@(luaL_checkstring(L, 3)), &error);
	if (!model) {
		lua_pushnil(L);
		lua_pushstring(L, error.UTF8String);
		return 2;
	}
	SCNNode *content = state.contents[handle];
	for (SCNNode *child in [content.childNodes copy]) [child removeFromParentNode];
	[content addChildNode:model];
	lua_pushboolean(L, 1);
	return 1;
}

/* A rounded rectangle extruded `length` deep with rounded edges: the body
 * of a phone, a tablet or a display. SceneKit centres the shape on its
 * path's bounds and extrudes along z. */
static SCNGeometry *reel_rounded_slab(double width, double height, double length, double corner, double chamfer) {
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(-width / 2, -height / 2, width, height)
		xRadius:corner yRadius:corner];
	// Curves become flat segments this long, in scene units; fine enough
	// that a device corner never shows facets at close range.
	path.flatness = MIN(width, height) * 0.002;
	SCNShape *shape = [SCNShape shapeWithPath:path extrusionDepth:length];
	shape.chamferRadius = MIN(chamfer, length / 2);
	shape.chamferMode = SCNChamferModeBoth;
	NSBezierPath *profile = [NSBezierPath bezierPath];
	// A quarter circle, so the chamfer reads as a rounded edge.
	[profile moveToPoint:NSMakePoint(0, 1)];
	[profile curveToPoint:NSMakePoint(1, 0) controlPoint1:NSMakePoint(0.55, 1) controlPoint2:NSMakePoint(1, 0.55)];
	shape.chamferProfile = profile;
	return shape;
}

/* geometry(handle, kind, {width, height, length, radius, chamfer,
 * cornerRadius}) -> true, or nil and a message. Kinds: box, sphere,
 * cylinder, cone, plane, floor, capsule, torus, slab (a rounded rectangle
 * extruded `length` deep with rounded edges). */
static int reel_scene_geometry(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	NSUInteger handle = reel_scene_handle(L, state, 2);
	const char *kind = luaL_checkstring(L, 3);
	luaL_checktype(L, 4, LUA_TTABLE);
	double width = reel_field(L, 4, "width", 1), height = reel_field(L, 4, "height", 1);
	double length = reel_field(L, 4, "length", 1), radius = reel_field(L, 4, "radius", 0.5);
	double chamfer = reel_field(L, 4, "chamfer", 0), corner = reel_field(L, 4, "cornerRadius", 0);
	SCNGeometry *geometry = nil;
	if (strcmp(kind, "box") == 0) geometry = [SCNBox boxWithWidth:width height:height length:length chamferRadius:chamfer];
	else if (strcmp(kind, "sphere") == 0) geometry = [SCNSphere sphereWithRadius:radius];
	else if (strcmp(kind, "cylinder") == 0) geometry = [SCNCylinder cylinderWithRadius:radius height:height];
	else if (strcmp(kind, "cone") == 0) geometry = [SCNCone coneWithTopRadius:0 bottomRadius:radius height:height];
	else if (strcmp(kind, "capsule") == 0) geometry = [SCNCapsule capsuleWithCapRadius:radius height:height];
	else if (strcmp(kind, "torus") == 0) geometry = [SCNTorus torusWithRingRadius:radius pipeRadius:reel_field(L, 4, "pipe", radius / 4)];
	else if (strcmp(kind, "slab") == 0) geometry = reel_rounded_slab(width, height, length, corner, chamfer);
	else if (strcmp(kind, "plane") == 0) {
		SCNPlane *plane = [SCNPlane planeWithWidth:width height:height];
		plane.cornerRadius = corner;
		// Enough segments for a smooth rounded corner.
		plane.cornerSegmentCount = 16;
		geometry = plane;
	} else if (strcmp(kind, "floor") == 0) {
		SCNFloor *floor = [SCNFloor floor];
		floor.reflectivity = reel_field(L, 4, "reflectivity", 0);
		floor.reflectionFalloffEnd = reel_field(L, 4, "reflectionFalloff", 0);
		geometry = floor;
	}
	if (!geometry) {
		lua_pushnil(L);
		lua_pushfstring(L, "unknown geometry '%s'", kind);
		return 2;
	}
	SCNNode *content = state.contents[handle];
	for (SCNNode *child in [content.childNodes copy]) [child removeFromParentNode];
	content.geometry = geometry;
	lua_pushboolean(L, 1);
	return 1;
}

/* material(handle, {color, emission, metalness, roughness, lighting,
 * doubleSided, transparency, clearcoat, clearcoatRoughness, order,
 * writesDepth, readsDepth, blend}): the content geometry's material. A
 * model's own materials are left alone. `lighting` is physical (default
 * when metalness or roughness is given), blinn, lambert or constant. */
static int reel_scene_material(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	NSUInteger handle = reel_scene_handle(L, state, 2);
	luaL_checktype(L, 3, LUA_TTABLE);
	SCNGeometry *geometry = state.contents[handle].geometry;
	if (!geometry) return 0;
	SCNMaterial *material = geometry.firstMaterial ?: [SCNMaterial material];
	geometry.firstMaterial = material;
	NSString *lighting = reel_field_string(L, 3, "lighting");
	lua_getfield(L, 3, "metalness");
	lua_getfield(L, 3, "roughness");
	BOOL physical = !lua_isnil(L, -1) || !lua_isnil(L, -2);
	lua_pop(L, 2);
	if ([lighting isEqualToString:@"constant"]) material.lightingModelName = SCNLightingModelConstant;
	else if ([lighting isEqualToString:@"lambert"]) material.lightingModelName = SCNLightingModelLambert;
	else if ([lighting isEqualToString:@"blinn"]) material.lightingModelName = SCNLightingModelBlinn;
	else if ([lighting isEqualToString:@"physical"] || physical) material.lightingModelName = SCNLightingModelPhysicallyBased;
	NSColor *color = reel_field_color(L, 3, "color");
	if (color) material.diffuse.contents = color;
	NSColor *emission = reel_field_color(L, 3, "emission");
	if (emission) material.emission.contents = emission;
	material.metalness.contents = @(reel_field(L, 3, "metalness", 0));
	material.roughness.contents = @(reel_field(L, 3, "roughness", 0.5));
	material.clearCoat.contents = @(reel_field(L, 3, "clearcoat", 0));
	material.clearCoatRoughness.contents = @(reel_field(L, 3, "clearcoatRoughness", 0.05));
	material.doubleSided = reel_field_bool(L, 3, "doubleSided", NO);
	material.transparency = reel_field(L, 3, "transparency", 1);
	material.writesToDepthBuffer = reel_field_bool(L, 3, "writesDepth", YES);
	material.readsFromDepthBuffer = reel_field_bool(L, 3, "readsDepth", YES);
	NSString *blend = reel_field_string(L, 3, "blend");
	material.blendMode = [blend isEqualToString:@"add"] ? SCNBlendModeAdd
		: [blend isEqualToString:@"screen"] ? SCNBlendModeScreen : SCNBlendModeAlpha;
	state.nodes[handle].renderingOrder = (NSInteger)reel_field(L, 3, "order", 0);
	return 0;
}

/* texture(handle, image, slot): shows an Image (a capture, a piece, a
 * rendered surface) on the content geometry, in the `slot` "emission"
 * (default: self-lit, as a display is) or "diffuse"; nil clears it.
 * Setting the image that is already there costs nothing. */
static int reel_scene_texture(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	NSUInteger handle = reel_scene_handle(L, state, 2);
	SCNGeometry *geometry = state.contents[handle].geometry;
	if (!geometry) return luaL_error(L, "scene node %d has no geometry to texture", (int)handle);
	const char *slot = luaL_optstring(L, 4, "emission");
	SCNMaterial *material = geometry.firstMaterial;
	SCNMaterialProperty *property = strcmp(slot, "diffuse") == 0 ? material.diffuse : material.emission;
	id contents = lua_isnil(L, 3) ? nil : (__bridge id)reel_check_image(L, 3)->image;
	if (property.contents == contents) return 0;
	property.contents = contents;
	property.mipFilter = SCNFilterModeLinear;
	property.minificationFilter = SCNFilterModeLinear;
	property.magnificationFilter = SCNFilterModeLinear;
	property.maxAnisotropy = SceneTextureAnisotropy;
	// A display emits its picture and reflects the room like black glass.
	if (strcmp(slot, "emission") == 0) material.diffuse.contents = NSColor.blackColor;
	return 0;
}

/* pose(handle, x, y, z, pitch, yaw, roll, sx, sy, sz, opacity, hidden):
 * the outer node; angles in radians, applied as SceneKit's euler angles. */
static int reel_scene_pose(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *node = state.nodes[reel_scene_handle(L, state, 2)];
	node.position = SCNVector3Make(luaL_checknumber(L, 3), luaL_checknumber(L, 4), luaL_checknumber(L, 5));
	node.eulerAngles = SCNVector3Make(luaL_checknumber(L, 6), luaL_checknumber(L, 7), luaL_checknumber(L, 8));
	node.scale = SCNVector3Make(luaL_checknumber(L, 9), luaL_checknumber(L, 10), luaL_checknumber(L, 11));
	node.opacity = luaL_optnumber(L, 12, 1);
	node.hidden = lua_toboolean(L, 13);
	return 0;
}

/* aim(handle, tx, ty, tz, roll): turns the outer node's -z toward a point in
 * its parent's space, world up, then rolls it about that axis (radians). */
static int reel_scene_aim(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *node = state.nodes[reel_scene_handle(L, state, 2)];
	SCNVector3 target = SCNVector3Make(luaL_checknumber(L, 3), luaL_checknumber(L, 4), luaL_checknumber(L, 5));
	if (node.parentNode) target = [node.parentNode convertPosition:target toNode:nil];
	[node lookAt:target up:SCNVector3Make(0, 1, 0) localFront:SCNVector3Make(0, 0, -1)];
	double roll = luaL_optnumber(L, 6, 0);
	if (roll != 0) node.simdOrientation = simd_mul(node.simdOrientation, simd_quaternion((float)roll, simd_make_float3(0, 0, 1)));
	return 0;
}

/* inner(handle, dy, pitch, yaw, roll): the content node's offset and turn,
 * for idle motion (a coin's spin and bob) that must not disturb the pose. */
static int reel_scene_inner(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *content = state.contents[reel_scene_handle(L, state, 2)];
	content.position = SCNVector3Make(0, luaL_checknumber(L, 3), 0);
	content.eulerAngles = SCNVector3Make(luaL_checknumber(L, 4), luaL_checknumber(L, 5), luaL_checknumber(L, 6));
	return 0;
}

// shadows(handle, casts): whether the node's content casts shadows.
static int reel_scene_shadows(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *content = state.contents[reel_scene_handle(L, state, 2)];
	BOOL casts = lua_toboolean(L, 3);
	[content enumerateHierarchyUsingBlock:^(SCNNode *child, BOOL *stop) { (void)stop; child.castsShadow = casts; }];
	return 0;
}

/* camera(handle, {fieldOfView, axis, zNear, zFar, focusDistance, fStop,
 * bloom, bloomThreshold, exposure, vignetting, hdr}): a lens on the node.
 * A focus distance turns depth of field on; bloom and exposure need hdr. */
static int reel_scene_camera(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *node = state.nodes[reel_scene_handle(L, state, 2)];
	luaL_checktype(L, 3, LUA_TTABLE);
	SCNCamera *camera = node.camera ?: [SCNCamera camera];
	node.camera = camera;
	camera.fieldOfView = reel_field(L, 3, "fieldOfView", 45);
	NSString *axis = reel_field_string(L, 3, "axis");
	camera.projectionDirection = [axis isEqualToString:@"horizontal"]
		? SCNCameraProjectionDirectionHorizontal : SCNCameraProjectionDirectionVertical;
	camera.zNear = reel_field(L, 3, "zNear", 0.05);
	camera.zFar = reel_field(L, 3, "zFar", 500);
	double focus = reel_field(L, 3, "focusDistance", 0);
	camera.wantsDepthOfField = focus > 0;
	if (focus > 0) {
		camera.focusDistance = focus;
		camera.fStop = reel_field(L, 3, "fStop", 5.6);
		camera.focalBlurSampleCount = 16;
	}
	camera.wantsHDR = reel_field_bool(L, 3, "hdr", NO);
	camera.bloomIntensity = reel_field(L, 3, "bloom", 0);
	camera.bloomThreshold = reel_field(L, 3, "bloomThreshold", 1);
	camera.exposureOffset = reel_field(L, 3, "exposure", 0);
	camera.vignettingIntensity = reel_field(L, 3, "vignetting", 0);
	camera.vignettingPower = 1;
	camera.wantsExposureAdaptation = NO;
	return 0;
}

/* light(handle, {type, intensity, color, temperature, castsShadow,
 * shadowRadius, shadowOpacity, shadowMapSize, shadowScale, spotInner,
 * spotOuter}): `type` is directional (default), ambient, omni or spot. */
static int reel_scene_light(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *node = state.nodes[reel_scene_handle(L, state, 2)];
	luaL_checktype(L, 3, LUA_TTABLE);
	SCNLight *light = node.light ?: [SCNLight light];
	node.light = light;
	NSString *type = reel_field_string(L, 3, "type");
	light.type = [type isEqualToString:@"ambient"] ? SCNLightTypeAmbient
		: [type isEqualToString:@"omni"] ? SCNLightTypeOmni
		: [type isEqualToString:@"spot"] ? SCNLightTypeSpot : SCNLightTypeDirectional;
	light.intensity = reel_field(L, 3, "intensity", 1000);
	light.color = reel_field_color(L, 3, "color") ?: NSColor.whiteColor;
	light.temperature = reel_field(L, 3, "temperature", 6500);
	light.spotInnerAngle = reel_field(L, 3, "spotInner", 0);
	light.spotOuterAngle = reel_field(L, 3, "spotOuter", 45);
	light.castsShadow = reel_field_bool(L, 3, "castsShadow", NO);
	if (light.castsShadow) {
		double size = reel_field(L, 3, "shadowMapSize", 2048);
		light.shadowMode = SCNShadowModeForward;
		light.shadowRadius = reel_field(L, 3, "shadowRadius", 4);
		light.shadowSampleCount = (NSUInteger)reel_field(L, 3, "shadowSamples", 16);
		light.shadowMapSize = CGSizeMake(size, size);
		light.shadowColor = [NSColor colorWithWhite:0 alpha:reel_field(L, 3, "shadowOpacity", 0.35)];
		double scale = reel_field(L, 3, "shadowScale", 0);
		if (scale > 0) {
			light.orthographicScale = scale;
			light.automaticallyAdjustsShadowProjection = NO;
		}
	}
	return 0;
}

// environment(image, intensity): image-based lighting and reflections from
// an equirectangular image; nil removes it.
static int reel_scene_environment(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	state.scene.lightingEnvironment.contents = lua_isnil(L, 2) ? nil : (__bridge id)reel_check_image(L, 2)->image;
	state.scene.lightingEnvironment.intensity = luaL_optnumber(L, 3, 1);
	return 0;
}

static void reel_scene_targets(ReelSceneState *state, NSUInteger width, NSUInteger height) {
	if (state.resolveTexture.width == width && state.resolveTexture.height == height) return;
	id<MTLDevice> device = reel_metal_device();
	MTLTextureDescriptor *color = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB
		width:width height:height mipmapped:NO];
	color.textureType = MTLTextureType2DMultisample;
	color.sampleCount = SceneSampleCount;
	color.usage = MTLTextureUsageRenderTarget;
	color.storageMode = MTLStorageModePrivate;
	state.colorTexture = [device newTextureWithDescriptor:color];
	MTLTextureDescriptor *resolve = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB
		width:width height:height mipmapped:NO];
	resolve.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	resolve.storageMode = MTLStorageModeShared;
	state.resolveTexture = [device newTextureWithDescriptor:resolve];
	MTLTextureDescriptor *depth = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
		width:width height:height mipmapped:NO];
	depth.textureType = MTLTextureType2DMultisample;
	depth.sampleCount = SceneSampleCount;
	depth.usage = MTLTextureUsageRenderTarget;
	depth.storageMode = MTLStorageModePrivate;
	state.depthTexture = [device newTextureWithDescriptor:depth];
}

/* render(camera, width, height) -> Image of that many pixels, seen through
 * the camera node, 4x multisampled; transparent where nothing was drawn,
 * premultiplied like every canvas. */
static int reel_scene_render(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *camera = state.nodes[reel_scene_handle(L, state, 2)];
	if (!camera.camera) return luaL_error(L, "scene node %d is not a camera", (int)lua_tointeger(L, 2));
	lua_Integer width = luaL_checkinteger(L, 3), height = luaL_checkinteger(L, 4);
	luaL_argcheck(L, width > 0 && height > 0, 3, "render needs a positive size");
	reel_scene_targets(state, (NSUInteger)width, (NSUInteger)height);
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = state.colorTexture;
	pass.colorAttachments[0].resolveTexture = state.resolveTexture;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
	pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
	pass.depthAttachment.texture = state.depthTexture;
	pass.depthAttachment.loadAction = MTLLoadActionClear;
	pass.depthAttachment.clearDepth = 1;
	pass.depthAttachment.storeAction = MTLStoreActionDontCare;
	// A reel runs no run loop, so the implicit transaction holding this
	// frame's poses would never commit on its own.
	[SCNTransaction flush];
	state.renderer.pointOfView = camera;
	id<MTLCommandBuffer> commands = [reel_metal_queue() commandBuffer];
	[state.renderer renderAtTime:0 viewport:CGRectMake(0, 0, width, height) commandBuffer:commands passDescriptor:pass];
	[commands commit];
	[commands waitUntilCompleted];
	if (commands.error) return luaL_error(L, "reel: scene render failed: %s", commands.error.localizedDescription.UTF8String);
	CGContextRef context = reel_bitmap((size_t)width, (size_t)height, NULL, (size_t)width * 4);
	[state.resolveTexture getBytes:CGBitmapContextGetData(context) bytesPerRow:CGBitmapContextGetBytesPerRow(context)
		fromRegion:MTLRegionMake2D(0, 0, (NSUInteger)width, (NSUInteger)height) mipmapLevel:0];
	CGImageRef image = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	reel_push_image(L, image, 1);
	return 1;
}

/* project(camera, width, height, x, y, z) -> px, py, depth: where a world
 * point lands in a render of that size (origin top-left), and its distance
 * along the view axis (negative behind the camera). */
static int reel_scene_project(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *camera = state.nodes[reel_scene_handle(L, state, 2)];
	if (!camera.camera) return luaL_error(L, "scene node %d is not a camera", (int)lua_tointeger(L, 2));
	double width = luaL_checknumber(L, 3), height = luaL_checknumber(L, 4);
	SCNVector3 world = SCNVector3Make(luaL_checknumber(L, 5), luaL_checknumber(L, 6), luaL_checknumber(L, 7));
	SCNVector3 view = [camera convertPosition:world fromNode:nil];
	SCNMatrix4 projection = [camera.camera projectionTransformWithViewportSize:CGSizeMake(width, height)];
	double x = view.x, y = view.y, z = view.z;
	double cx = projection.m11 * x + projection.m21 * y + projection.m31 * z + projection.m41;
	double cy = projection.m12 * x + projection.m22 * y + projection.m32 * z + projection.m42;
	double cw = projection.m14 * x + projection.m24 * y + projection.m34 * z + projection.m44;
	if (cw == 0) cw = 1e-9;
	lua_pushnumber(L, (cx / cw * 0.5 + 0.5) * width);
	lua_pushnumber(L, (0.5 - cy / cw * 0.5) * height);
	lua_pushnumber(L, -z);
	return 3;
}

/* extent(handle, camera, width, height) -> minX, minY, maxX, maxY: the
 * node's bounding box (children included) projected into a render of that
 * size, or nothing when the box is wholly behind the camera. A surface uses
 * it to skip drawing what is off screen and to draw small what is far. */
static int reel_scene_extent(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *node = state.nodes[reel_scene_handle(L, state, 2)];
	SCNNode *camera = state.nodes[reel_scene_handle(L, state, 3)];
	if (!camera.camera) return luaL_error(L, "scene node %d is not a camera", (int)lua_tointeger(L, 3));
	double width = luaL_checknumber(L, 4), height = luaL_checknumber(L, 5);
	[SCNTransaction flush];
	SCNVector3 lo, hi;
	if (![node getBoundingBoxMin:&lo max:&hi]) return 0;
	SCNMatrix4 projection = [camera.camera projectionTransformWithViewportSize:CGSizeMake(width, height)];
	double minX = INFINITY, minY = INFINITY, maxX = -INFINITY, maxY = -INFINITY;
	BOOL front = NO;
	for (int i = 0; i < 8; i++) {
		SCNVector3 corner = SCNVector3Make(i & 1 ? hi.x : lo.x, i & 2 ? hi.y : lo.y, i & 4 ? hi.z : lo.z);
		SCNVector3 view = [camera convertPosition:corner fromNode:node];
		// Points behind the camera are clamped onto the near plane side, so
		// a box the camera is inside still covers the frame.
		double z = MIN(view.z, -camera.camera.zNear);
		if (view.z < 0) front = YES;
		double cx = projection.m11 * view.x + projection.m21 * view.y + projection.m31 * z + projection.m41;
		double cy = projection.m12 * view.x + projection.m22 * view.y + projection.m32 * z + projection.m42;
		double cw = projection.m14 * view.x + projection.m24 * view.y + projection.m34 * z + projection.m44;
		if (cw <= 0) cw = 1e-6;
		double px = (cx / cw * 0.5 + 0.5) * width, py = (0.5 - cy / cw * 0.5) * height;
		minX = MIN(minX, px); maxX = MAX(maxX, px); minY = MIN(minY, py); maxY = MAX(maxY, py);
	}
	if (!front) return 0;
	lua_pushnumber(L, minX); lua_pushnumber(L, minY); lua_pushnumber(L, maxX); lua_pushnumber(L, maxY);
	return 4;
}

/* world(handle, x, y, z) -> x, y, z: a point in the node's space in world
 * coordinates, after this frame's poses. */
static int reel_scene_world(lua_State *L) {
	ReelSceneState *state = reel_check_scene(L, 1);
	SCNNode *node = state.nodes[reel_scene_handle(L, state, 2)];
	[SCNTransaction flush];
	SCNVector3 world = [node convertPosition:SCNVector3Make(luaL_checknumber(L, 3), luaL_checknumber(L, 4),
		luaL_checknumber(L, 5)) toNode:nil];
	lua_pushnumber(L, world.x);
	lua_pushnumber(L, world.y);
	lua_pushnumber(L, world.z);
	return 3;
}

static int reel_scene_gc(lua_State *L) {
	ReelSceneBox *box = luaL_checkudata(L, 1, SceneMetatable);
	if (box->state) {
		ReelSceneState *state = (__bridge_transfer ReelSceneState *)box->state;
		box->state = NULL;
		state.renderer.scene = nil;
	}
	return 0;
}

static const luaL_Reg reel_scene_methods[] = {
	{"node", reel_scene_node}, {"model", reel_scene_model}, {"geometry", reel_scene_geometry},
	{"material", reel_scene_material}, {"texture", reel_scene_texture}, {"pose", reel_scene_pose},
	{"aim", reel_scene_aim}, {"inner", reel_scene_inner}, {"shadows", reel_scene_shadows},
	{"camera", reel_scene_camera}, {"light", reel_scene_light}, {"environment", reel_scene_environment},
	{"render", reel_scene_render}, {"project", reel_scene_project},
	{"world", reel_scene_world},
	{"extent", reel_scene_extent},
	{NULL, NULL}};
