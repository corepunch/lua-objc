/* Shared mesh-gradient rasterizer used by AppKit and UIKit views.
 * Parameter-space bilinear interpolation over a width×height control grid.
 * Point positions warp the sample coordinates the same way SwiftUI's
 * MeshGradient does for a small animated grid. */

typedef struct {
	float x, y;
	float r, g, b, a;
} LuaMeshNode;

static const LuaMeshNode kMeshGradientDefaultNodes[9] = {
	{0.00f, 0.00f, 0.01f, 0.01f, 0.03f, 1},
	{0.50f, 0.00f, 0.12f, 0.04f, 0.28f, 1},
	{1.00f, 0.00f, 0.02f, 0.02f, 0.06f, 1},
	{0.00f, 0.50f, 0.18f, 0.05f, 0.22f, 1},
	{0.50f, 0.50f, 0.85f, 0.78f, 1.00f, 1},
	{1.00f, 0.50f, 0.08f, 0.22f, 0.55f, 1},
	{0.00f, 1.00f, 0.00f, 0.00f, 0.02f, 1},
	{0.50f, 1.00f, 0.25f, 0.06f, 0.18f, 1},
	{1.00f, 1.00f, 0.01f, 0.02f, 0.05f, 1},
};

static LuaMeshNode *mesh_gradient_nodes_from_lua(lua_State *L, int width, int height,
	int pointArg, int colorArg)
{
	int count = width * height;
	LuaMeshNode *nodes = malloc(sizeof(LuaMeshNode) * (size_t)count);
	if (!nodes) luaL_error(L, "MeshGradient could not allocate grid nodes");
	for (int i = 0; i < count; i++) {
		nodes[i] = kMeshGradientDefaultNodes[i % 9];
		nodes[i].x = (float)(i % width) / (float)(width - 1);
		nodes[i].y = (float)(i / width) / (float)(height - 1);
	}
	if (lua_istable(L, pointArg)) {
		for (int i = 0; i < count; i++) {
			lua_rawgeti(L, pointArg, i + 1);
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
	if (lua_istable(L, colorArg)) {
		for (int i = 0; i < count; i++) {
			lua_rawgeti(L, colorArg, i + 1);
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
	return nodes;
}

static void mesh_gradient_animate_points(LuaMeshNode *nodes, int width, int height,
	NSTimeInterval t)
{
	if (width != 3 || height != 3) return;
	float x = sinf((float)t * 1.35f) * 0.28f + 0.50f;
	float y = cosf((float)t * 1.05f) * 0.24f + 0.50f;
	float e = sinf((float)t * 1.20f) * 0.10f;
	nodes[0].x = 0;       nodes[0].y = 0;
	nodes[1].x = 0.5f + e; nodes[1].y = 0;
	nodes[2].x = 1;       nodes[2].y = 0;
	nodes[3].x = 0;       nodes[3].y = 0.5f - e;
	nodes[4].x = x;       nodes[4].y = y;
	nodes[5].x = 1;       nodes[5].y = 0.5f + e;
	nodes[6].x = 0;       nodes[6].y = 1;
	nodes[7].x = 0.5f - e; nodes[7].y = 1;
	nodes[8].x = 1;       nodes[8].y = 1;
}

static void mesh_gradient_sample(const LuaMeshNode *nodes, int cols, int rows,
	float u, float v, float *r, float *g, float *b, float *a)
{
	if (cols < 2 || rows < 2) {
		*r = *g = *b = 0;
		*a = 1;
		return;
	}
	float gx = fminf(fmaxf(u, 0) * (cols - 1), cols - 1.0001f);
	float gy = fminf(fmaxf(v, 0) * (rows - 1), rows - 1.0001f);
	int x0 = (int)gx;
	int y0 = (int)gy;
	int x1 = x0 + 1;
	int y1 = y0 + 1;
	float tx = gx - x0;
	float ty = gy - y0;
	const LuaMeshNode *c00 = &nodes[y0 * cols + x0];
	const LuaMeshNode *c10 = &nodes[y0 * cols + x1];
	const LuaMeshNode *c01 = &nodes[y1 * cols + x0];
	const LuaMeshNode *c11 = &nodes[y1 * cols + x1];
	float wx = (1 - tx) * ((1 - ty) * c00->x + ty * c01->x)
		+ tx * ((1 - ty) * c10->x + ty * c11->x);
	float wy = (1 - tx) * ((1 - ty) * c00->y + ty * c01->y)
		+ tx * ((1 - ty) * c10->y + ty * c11->y);
	/* Pull the sample toward the warped control point so the bright
	 * interior node travels across the mesh the way TimelineView does. */
	float su = u + (wx - (x0 + tx) / (cols - 1)) * 0.65f;
	float sv = v + (wy - (y0 + ty) / (rows - 1)) * 0.65f;
	gx = fminf(fmaxf(su, 0) * (cols - 1), cols - 1.0001f);
	gy = fminf(fmaxf(sv, 0) * (rows - 1), rows - 1.0001f);
	x0 = (int)gx; y0 = (int)gy; x1 = x0 + 1; y1 = y0 + 1;
	tx = gx - x0; ty = gy - y0;
	c00 = &nodes[y0 * cols + x0];
	c10 = &nodes[y0 * cols + x1];
	c01 = &nodes[y1 * cols + x0];
	c11 = &nodes[y1 * cols + x1];
	float s00 = (1 - tx) * (1 - ty);
	float s10 = tx * (1 - ty);
	float s01 = (1 - tx) * ty;
	float s11 = tx * ty;
	*r = s00 * c00->r + s10 * c10->r + s01 * c01->r + s11 * c11->r;
	*g = s00 * c00->g + s10 * c10->g + s01 * c01->g + s11 * c11->g;
	*b = s00 * c00->b + s10 * c10->b + s01 * c01->b + s11 * c11->b;
	*a = s00 * c00->a + s10 * c10->a + s01 * c01->a + s11 * c11->a;
}

static CGImageRef mesh_gradient_image(const LuaMeshNode *nodes, int cols, int rows,
	int width, int height)
{
	if (width < 1 || height < 1) return NULL;
	size_t bytes = (size_t)width * (size_t)height * 4;
	uint8_t *pixels = malloc(bytes);
	if (!pixels) return NULL;
	for (int y = 0; y < height; y++) {
		float v = height == 1 ? 0 : (float)y / (float)(height - 1);
		uint8_t *row = pixels + (size_t)y * (size_t)width * 4;
		for (int x = 0; x < width; x++) {
			float u = width == 1 ? 0 : (float)x / (float)(width - 1);
			float r, g, b, a;
			mesh_gradient_sample(nodes, cols, rows, u, v, &r, &g, &b, &a);
			row[x * 4 + 0] = (uint8_t)(fminf(fmaxf(r, 0), 1) * 255);
			row[x * 4 + 1] = (uint8_t)(fminf(fmaxf(g, 0), 1) * 255);
			row[x * 4 + 2] = (uint8_t)(fminf(fmaxf(b, 0), 1) * 255);
			row[x * 4 + 3] = (uint8_t)(fminf(fmaxf(a, 0), 1) * 255);
		}
	}
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space,
		kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGImageRef image = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
	if (ctx) CGContextRelease(ctx);
	CGColorSpaceRelease(space);
	free(pixels);
	return image;
}
