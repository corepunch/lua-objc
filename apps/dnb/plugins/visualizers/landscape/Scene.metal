// Valley Flight — a drone flyover of alpine peaks at twilight. World units:
// y is up and the tarns' surface is y = 0. The terrain never moves: it is
// drawn as CDLOD-style nested grids (Strugar, "Continuous Distance-Dependent
// Level of Detail"). Each level doubles the cell size of the one inside it
// and keeps a hole where the finer level lies; all levels are snapped to the
// coarsest cell, so every vertex sits on a fixed world lattice. Towards its
// outer edge a level's odd vertices slide onto their even neighbours, so it
// meets the next level without cracks or pops. Heights and normals come
// from one pass of analytic-derivative noise per vertex, plus sparse
// pyramidal summits so a peak can fill the frame the way a high Himalayan
// face does. The water is one plane, drawn after the terrain so the depth
// test leaves only the flooded tarns, and the sky is drawn last at the far
// plane so its stars are shaded only where nothing covers them. Distance
// fades into the same haze as the sky. The drone stays in the valleys,
// yawing through soft turns and banking into them, looking up at the faces.

constant float LAND_SPEED = 2.4;         // world units per unit of travel
constant float LAND_WATER_FOG = 0.014;   // haze density per world unit
constant float LAND_CLOUD_HEIGHT = 22.0; // the sky's thin cloud deck
constant float LAND_FAR = 110.0;         // the haze is complete here
constant float LAND_ALTITUDE = 3.1;      // cruise height in the valleys
constant float LAND_CLEARANCE = 1.7;     // lift over a ridge that blocks the path
constant float LAND_BANK = 3.0;          // roll per unit of path curvature
constant float LAND_MAX_BANK = 0.22;     // radians
constant float LAND_GRID_AHEAD = 10.0;   // the grids' centre ahead of the drone
constant float LAND_CELL = 0.35;         // the finest level's cell
constant int LAND_LEVELS = 3;            // nested grid levels, each twice as coarse
constant int LAND_SIDE = 128;            // cells along a level's side
constant int LAND_STRIP = 32;            // cells in one instanced triangle strip
constant float LAND_MORPH = 16.0;        // cells over which a level morphs into the next
constant float LAND_BANK_CELL = 22.0;    // one cloud bank per world cell at most

// The drone's ground track at distance u: a forward drift with lateral and
// longitudinal swings, so its heading sways well off the drift.
static float2 landPath(float u) {
	return float2(26.0 * sin(u * 0.031) + 9.0 * sin(u * 0.077 + 1.0), u + 14.0 * sin(u * 0.043 + 2.0));
}

static float2 landVelocity(float u) {
	return float2(26.0 * 0.031 * cos(u * 0.031) + 9.0 * 0.077 * cos(u * 0.077 + 1.0),
		1.0 + 14.0 * 0.043 * cos(u * 0.043 + 2.0));
}

static float2 landAcceleration(float u) {
	return float2(-26.0 * 0.031 * 0.031 * sin(u * 0.031) - 9.0 * 0.077 * 0.077 * sin(u * 0.077 + 1.0),
		-14.0 * 0.043 * 0.043 * sin(u * 0.043 + 2.0));
}

// A low sun off the right-hand face: warm grazing light, long blue shadow.
static float3 landSun(const thread Frame &f) {
	return normalize(float3(0.88, 0.07 + 0.02 * sin(f.t * 0.018), 0.22));
}

static float2 landRotate(float2 q) {
	return float2(q.x * 1.7 - q.y * 1.1, q.x * 1.1 + q.y * 1.7);
}

// Ridged alpine massifs with sparse pyramidal summits. Returns the height
// and its gradient, carried through each octave's rotation.
static float3 landTerrain(float2 p) {
	float h = 0.0, a = 0.55;
	float2 slope = 0.0;
	float2 q = p * 0.052;
	float2 qx = float2(0.052, 0.0), qz = float2(0.0, 0.052);
	for (int o = 0; o < 6; o++) {
		float3 n = noised(q);
		float r = 1.0 - abs(n.x * 2.0 - 1.0);
		float2 dr = -2.0 * sign(n.x * 2.0 - 1.0) * n.yz;
		h += a * r * r;
		float2 g = 2.0 * a * r * dr;
		slope += float2(dot(g, qx), dot(g, qz));
		q = landRotate(q) + 5.3;
		qx = landRotate(qx);
		qz = landRotate(qz);
		a *= 0.5;
	}
	// Cube the ridges so peaks stand up and valleys stay low.
	float shaped = 1.2 * h * h * h;
	float2 dShaped = 1.2 * 3.0 * h * h * slope;

	float spacing = 38.0;
	float2 id = floor(p / spacing);
	float2 local = fract(p / spacing);
	float2 jitter = hash22(id) - 0.5;
	float2 offset = (local - 0.5 - jitter * 0.3) * spacing;
	float rad = length(offset);
	float seed = hash21(id + 2.7);
	float reach = 8.0 + 7.5 * seed;
	float amp = (7.0 + 12.0 * seed) * step(0.3, seed);
	float t = saturate(1.0 - rad / max(reach, 1e-3));
	float k = 1.4;
	float cone = pow(t, k) * amp;
	float2 dCone = 0.0;
	if (amp > 0.0 && rad > 1e-3 && rad < reach) {
		float dCdR = k * pow(t, k - 1.0) * amp * (-1.0 / reach);
		dCone = dCdR * offset / rad;
	}

	float3 crag = noised(p * 0.62);
	return float3(-0.2 + shaped * 10.0 + cone + 0.28 * crag.x,
		dShaped * 10.0 + dCone + 0.28 * 0.62 * crag.yz);
}

static Camera landCamera(const thread Frame &f) {
	float u = f.travel * LAND_SPEED;
	float2 ground = landPath(u);
	float2 v = landVelocity(u);
	float2 a = landAcceleration(u);
	float2 heading = normalize(landVelocity(u + 3.0));
	float floorH = landTerrain(ground).x;
	float aheadH = landTerrain(ground + heading * 16.0).x;
	float eyeY = max(LAND_ALTITUDE, floorH + LAND_CLEARANCE) + 0.28 * sin(u * 0.05) + 0.05 * sin(f.t * 0.7);
	float3 eye = float3(ground.x, eyeY, ground.y);
	// Look along the track toward the face ahead, pitched up at the summit
	// rather than down at the valley floor.
	float lookY = mix(eyeY + 0.4, max(aheadH * 0.62, eyeY + 1.2), 0.85);
	float3 target = eye + float3(heading.x * 7.5, lookY - eyeY, heading.y * 7.5);
	float curvature = (v.x * a.y - v.y * a.x) / pow(length(v), 3.0);
	float roll = clamp(curvature * LAND_BANK, -LAND_MAX_BANK, LAND_MAX_BANK);
	return lookAt(eye, target, 1.55, roll);
}

// Sky light along a direction: navy zenith, a thin gold twilight, the sun
// and its glow; `stars` adds the night field (skipped for haze).
static float3 landSky(float3 dir, float3 eye, const thread Frame &f, bool stars) {
	float3 sun = landSun(f);
	float e = dir.y;
	float3 twilight = mix(float3(1.0, 0.52, 0.22), neon(f.hue + 0.04), 0.08);
	float3 zenith = float3(0.012, 0.03, 0.09);
	float3 colour = mix(twilight, zenith, pow(saturate(e * 1.35 + 0.04), 0.42));
	colour = mix(colour, twilight * 0.28, smoothstep(0.02, -0.18, e));
	float s = saturate(dot(dir, sun));
	float glow = 1.0 + 0.8 * f.kick * f.presence;
	colour += float3(1.0, 0.62, 0.28) * (pow(s, 28.0) * 0.7 + pow(s, 5.0) * 0.18) * glow;
	if (!stars) return colour;
	colour += float3(1.0, 0.88, 0.62) * smoothstep(0.9988, 0.9996, s) * 7.0 * glow;
	if (e > 0.08) {
		float3 cell = dir * 180.0;
		float field = hash31(floor(cell));
		float speck = smoothstep(0.973, 0.995, field) * smoothstep(0.12, 0.55, e);
		colour += speck * (0.45 + 0.55 * hash31(floor(cell) + 3.1)) * (0.55 + 0.45 * f.high);
		float t = (LAND_CLOUD_HEIGHT - eye.y) / max(e, 0.02);
		float2 at = (eye + dir * t).xz * 0.02 + float2(f.t * 0.008, 0.0);
		float cover = smoothstep(0.62, 0.88, fbm(at, 4));
		float3 lit = mix(float3(0.18, 0.16, 0.28), float3(0.95, 0.7, 0.48), saturate(pow(s, 3.0)));
		colour = mix(colour, lit, cover * exp(-t * 0.006) * 0.35);
	}
	return colour;
}

static float3 landFog(float3 colour, float3 world, const thread Camera &cam, const thread Frame &f) {
	float3 ray = world - cam.eye;
	float d = length(ray);
	float amount = max(1.0 - exp(-d * LAND_WATER_FOG), smoothstep(LAND_FAR * 0.72, LAND_FAR, d));
	return mix(colour, landSky(ray / d, cam.eye, f, false), amount);
}

// The sky's covering triangle at the far plane: drawn after the terrain and
// water, the depth test shades only the uncovered pixels.
vertex ShaderVertex landscapeSkyVertex(uint id [[vertex_id]]) {
	float2 p = float2((id << 1) & 2, id & 2);
	ShaderVertex out;
	out.position = float4(p * 2.0 - 1.0, 1.0, 1.0);
	out.uv = float2(p.x, 1.0 - p.y);
	return out;
}

fragment float4 landscapeSkyFragment(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float3 dir = cameraRay(stagePoint(in.uv, f), cam);
	return float4(landSky(dir, cam.eye, f, true), 1.0);
}

// ---- Terrain

struct LandVertex {
	float4 position [[position]];
	float3 world;
	float3 normal;
};

// Instances are strips of LAND_STRIP cells: the finest level whole, then
// each coarser level as a ring around its hole — full-width rows above and
// below, the outer quarters beside it.
static int3 landStrip(int instance) {
	int perRow = LAND_SIDE / LAND_STRIP, quarter = LAND_SIDE / 4;
	int whole = LAND_SIDE * perRow;
	if (instance < whole) return int3(0, instance / perRow, instance % perRow);
	int ring = quarter * 2 * perRow + LAND_SIDE / 2 * 2;
	int k = (instance - whole) % ring, level = 1 + (instance - whole) / ring;
	int band = quarter * perRow;
	if (k < band) return int3(level, k / perRow, k % perRow);
	k -= band;
	if (k < band) return int3(level, LAND_SIDE - quarter + k / perRow, k % perRow);
	k -= band;
	return int3(level, quarter + k / 2, (k % 2) * (perRow - 1));
}

vertex LandVertex landscapeTerrainVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	int3 strip = landStrip(int(iid));
	float2 at = float2(strip.z * LAND_STRIP + int(vid / 2), strip.y + int(vid & 1));
	float cell = LAND_CELL * exp2(float(strip.x));
	float coarsest = LAND_CELL * exp2(float(LAND_LEVELS - 1));
	// Every level is centred on the same point, snapped to the coarsest
	// cell, so all of them stay on their world lattices.
	float2 forward = normalize(float2(cam.forward.x, cam.forward.z) + 1e-4);
	float2 centre = cam.eye.xz + forward * LAND_GRID_AHEAD;
	float2 snapped = floor(centre / coarsest + 0.5) * coarsest;
	float reach = float(LAND_SIDE / 2) * cell;
	float2 p = snapped - reach + at * cell;
	// Morph by the distance from the unsnapped centre, which moves smoothly:
	// complete before the level's edge however the snap falls.
	if (strip.x < LAND_LEVELS - 1) {
		float edge = max(abs(p.x - centre.x), abs(p.y - centre.y));
		float outer = reach - coarsest * 0.5;
		float k = saturate((edge - (outer - LAND_MORPH * cell)) / (LAND_MORPH * cell));
		p -= fract(at * 0.5) * 2.0 * cell * k;
	}
	float3 h = landTerrain(p);
	LandVertex out;
	out.world = float3(p.x, h.x, p.y);
	out.normal = normalize(float3(-h.y, 1.0, -h.z));
	out.position = cameraClip(out.world, f, cam);
	return out;
}

fragment float4 landscapeTerrainFragment(LandVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float3 n = normalize(in.normal);
	float h = in.world.y;
	float slope = 1.0 - n.y;
	float grain = noise(in.world.xz * 2.4);
	float crease = noise(in.world.xz * 7.0 + 4.1);
	// Snow on the faces, warm rock in the couloirs, blue shadow on the lee.
	float3 snow = float3(0.86, 0.9, 0.96);
	float3 rock = float3(0.38, 0.24, 0.16) * (0.75 + 0.45 * grain);
	float3 ice = float3(0.22, 0.3, 0.4);
	float snowAmt = smoothstep(1.4, 4.2, h + grain * 0.45) * smoothstep(0.78, 0.32, slope);
	float rockAmt = smoothstep(0.22, 0.55, slope);
	float3 colour = mix(ice, rock, rockAmt);
	colour = mix(colour, snow, snowAmt);
	colour = mix(colour, snow * float3(0.78, 0.84, 0.95), smoothstep(7.0, 11.0, h) * (1.0 - rockAmt * 0.4));
	colour *= 0.92 + 0.1 * crease;
	float3 sun = landSun(f);
	float lit = saturate(dot(n, sun));
	float wrap = saturate(dot(n, sun) * 0.5 + 0.5);
	float3 warm = float3(1.0, 0.68, 0.36) * lit * (1.55 + 0.55 * f.kick * f.presence);
	float3 cool = float3(0.1, 0.16, 0.32) * (0.28 + 0.5 * n.y + 0.18 * wrap);
	float3 light = warm + cool;
	// A thin glitter on sunlit snow when the highs or the kick land.
	light += float3(1.0, 0.92, 0.78) * snowAmt * lit * pow(saturate(dot(n, sun)), 8.0)
		* (0.08 + 0.35 * f.high * f.presence + 0.25 * f.kick * f.presence);
	return float4(landFog(colour * light, in.world, cam, f), 1.0);
}

// ---- Water: one plane around the drone, out past the haze.

struct LandWater {
	float4 position [[position]];
	float3 world;
};

vertex LandWater landscapeWaterVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, -1), float2(1, 1), float2(-1, 1)};
	float2 c = corners[vid];
	LandWater out;
	out.world = float3(cam.eye.x + c.x * LAND_FAR * 1.2, 0.0, cam.eye.z + c.y * LAND_FAR * 1.2);
	out.position = cameraClip(out.world, f, cam);
	return out;
}

// The wave field's gradient: three drifting octaves and a fast fine ripple.
static float2 landWaves(float2 p, const thread Frame &f) {
	float t = f.t * 0.6;
	float2 q = p * 1.6 + float2(t, t * 0.4);
	float2 qx = float2(1.6, 0.0), qz = float2(0.0, 1.6);
	float2 slope = 0.0;
	float a = 0.5;
	for (int o = 0; o < 3; o++) {
		float2 g = a * noised(q).yz;
		slope += float2(dot(g, qx), dot(g, qz));
		q = float2(q.x * 1.6 - q.y * 1.2, q.x * 1.2 + q.y * 1.6) + 3.1;
		qx = float2(qx.x * 1.6 - qx.y * 1.2, qx.x * 1.2 + qx.y * 1.6);
		qz = float2(qz.x * 1.6 - qz.y * 1.2, qz.x * 1.2 + qz.y * 1.6);
		a *= 0.5;
	}
	return slope + 0.5 * 6.0 * noised(p * 6.0 - float2(t * 1.7, 0.0)).yz;
}

fragment float4 landscapeWaterFragment(LandWater in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float3 view = normalize(in.world - cam.eye);
	float2 slope = landWaves(in.world.xz, f);
	float chop = 0.08 + 0.18 * f.high * f.presence;
	float3 n = normalize(float3(-slope.x * chop * 0.1, 1.0, -slope.y * chop * 0.1));
	float3 r = reflect(view, n);
	r.y = abs(r.y);
	float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(-dot(view, n)), 5.0);
	float3 deep = float3(0.015, 0.04, 0.07);
	float3 colour = mix(deep, landSky(r, in.world, f, true), fresnel);
	float3 sun = landSun(f);
	colour += float3(1.0, 0.78, 0.48) * pow(saturate(dot(r, sun)), 380.0) * (4.0 + 5.0 * f.kick * f.presence);
	return float4(landFog(colour, in.world, cam, f), 1.0);
}

// ---- Cloud banks: sparse high wisps, at most one per world cell in a
// square of cells around the drone. They hang still; the drone passes by
// and under them.

struct LandCloud {
	float4 position [[position]];
	float2 local;
	float fade [[flat]];
	float seed [[flat]];
};

vertex LandCloud landscapeCloudVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]], constant float *params [[buffer(2)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	int side = int(params[0]);
	float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, -1), float2(1, 1), float2(-1, 1)};
	float2 c = corners[vid];
	float2 id = floor(cam.eye.xz / LAND_BANK_CELL) + float2(int(iid) % side, int(iid) / side) - float(side / 2);
	float h1 = hash21(id + 1.7), h2 = hash21(id + 8.3), h3 = hash21(id + 4.1);
	float3 centre = float3((id.x + 0.2 + 0.6 * h1) * LAND_BANK_CELL, 14.0 + h2 * 5.0, (id.y + 0.2 + 0.6 * h3) * LAND_BANK_CELL);
	float radius = 2.4 + 3.0 * h3;
	float3 v = cameraView(centre, cam);
	LandCloud out;
	out.position = viewClip(float3(v.xy + c * radius * float2(1.8, 0.7), v.z), f, cam);
	out.local = c;
	float reach = LAND_BANK_CELL * float(side / 2);
	out.fade = smoothstep(2.0, 8.0, v.z) * smoothstep(reach, reach * 0.55, length(v)) * step(0.72, hash21(id + 2.2));
	out.seed = h1 * 17.0;
	return out;
}

fragment float4 landscapeCloudFragment(LandCloud in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	float2 p = in.local;
	float shape = fbm(p * 1.6 + in.seed + f.t * 0.02, 3);
	float density = saturate((1.0 - dot(p, p)) * 1.4 + shape - 0.9) * in.fade;
	if (density <= 0.0) discard_fragment();
	float lightSide = saturate(0.55 - p.y * 0.35 + shape * 0.35);
	float3 colour = mix(float3(0.28, 0.24, 0.36), float3(0.95, 0.72, 0.5), lightSide);
	float alpha = density * 0.65;
	return float4(colour * alpha, alpha);
}
