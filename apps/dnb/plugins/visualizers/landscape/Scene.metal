// Valley Flight — a low flight up a river valley at sunset. World units:
// y is up, the flight runs along +z and the river's surface is y = 0. The
// terrain is a grid mesh laid out ahead of the camera, rows spaced wider
// with distance and snapped to the world so peaks stay put as it flies; the
// water is one plane, drawn after the terrain so the depth test leaves only
// the flooded valley floor. Distance fades into the same haze as the sky.

constant float LAND_SPEED = 2.4;         // world units per unit of travel
constant float LAND_WATER_FOG = 0.022;   // haze density per world unit
constant float LAND_CLOUD_HEIGHT = 9.0;  // the sky's cloud deck
constant float LAND_BANK_SPACING = 3.2;  // cloud banks drift past this far apart
constant float LAND_FAR = 85.0;          // the grid's last row

static float landPath(float z) {
	return 3.5 * sin(z * 0.045) + 1.4 * sin(z * 0.11 + 1.0);
}

static float3 landSun(const thread Frame &f) {
	return normalize(float3(-0.28, 0.1 + 0.015 * sin(f.t * 0.02), 1.0));
}

// Ridged mountains, lowered into a valley around the flight path.
static float landHeight(float2 p) {
	float h = 0.0, a = 0.5;
	float2 q = p * 0.075;
	for (int o = 0; o < 5; o++) {
		float n = 1.0 - abs(noise(q) * 2.0 - 1.0);
		h += a * n * n;
		q = float2(q.x * 1.7 - q.y * 1.1, q.x * 1.1 + q.y * 1.7) + 5.3;
		a *= 0.48;
	}
	float valley = smoothstep(1.4, 7.5, abs(p.x - landPath(p.y)));
	return -0.35 + h * 3.6 * (0.12 + 0.88 * valley) + 0.08 * noise(p * 1.3);
}

static Camera landCamera(const thread Frame &f) {
	float z = f.travel * LAND_SPEED;
	float x = landPath(z);
	float ahead = landPath(z + 4.0);
	float3 eye = float3(x, 1.05 + 0.18 * sin(f.t * 0.23), z);
	// Bank into the river's bends.
	float roll = clamp((ahead - x) * 0.12, -0.2, 0.2);
	return lookAt(eye, float3(ahead, 0.72, z + 4.0), 1.8, roll);
}

// Sky light along a direction: blue overhead, gold at the horizon, the sun
// and its glow; `clouds` adds the cloud deck (skipped for haze).
static float3 landSky(float3 dir, float3 eye, const thread Frame &f, bool clouds) {
	float3 sun = landSun(f);
	float e = dir.y;
	float3 horizon = mix(float3(1.0, 0.56, 0.3), neon(f.hue + 0.05), 0.18);
	float3 zenith = float3(0.1, 0.17, 0.4);
	float3 colour = mix(horizon, zenith, pow(saturate(e * 1.5 + 0.02), 0.55));
	colour = mix(colour, horizon * 0.55, smoothstep(0.0, -0.2, e)); // below the horizon: haze
	float s = saturate(dot(dir, sun));
	float glow = 1.0 + 0.9 * f.kick * f.presence;
	colour += float3(1.0, 0.7, 0.4) * (pow(s, 40.0) * 0.55 + pow(s, 6.0) * 0.22) * glow;
	if (!clouds) return colour;
	colour += float3(1.0, 0.92, 0.75) * smoothstep(0.9993, 0.9997, s) * 8.0 * glow;
	if (e > 0.0) {
		float t = (LAND_CLOUD_HEIGHT - eye.y) / e;
		float2 at = (eye + dir * t).xz * 0.035 + float2(f.t * 0.01, 0.0);
		float cover = smoothstep(0.42, 0.78, fbm(at, 5));
		float thick = fbm(at * 2.0 + 4.0, 3);
		float3 lit = mix(float3(0.45, 0.32, 0.4), float3(1.0, 0.72, 0.5), saturate(pow(s, 3.0) + 0.3 * thick));
		lit = mix(lit, neon(f.hue + 0.8) * 0.8, 0.12);
		float distance = exp(-t * 0.004);
		colour = mix(colour, lit, cover * distance * 0.85);
	}
	return colour;
}

static float3 landFog(float3 colour, float3 world, const thread Camera &cam, const thread Frame &f) {
	float3 ray = world - cam.eye;
	float d = length(ray);
	float amount = 1.0 - exp(-d * LAND_WATER_FOG);
	return mix(colour, landSky(ray / d, cam.eye, f, false), amount);
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

// Distance of grid row i (0…rows) ahead of the camera.
static float landRow(float i, float rows) {
	float x = i / rows;
	return 0.25 + x * 10.0 + x * x * (LAND_FAR - 10.25);
}

vertex LandVertex landscapeTerrainVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]],
		constant float *params [[buffer(2)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	int rows = int(params[0]), columns = int(params[1]);
	int cell = int(vid / 6), corner = int(vid % 6);
	int2 offsets[6] = {int2(0, 0), int2(1, 0), int2(0, 1), int2(1, 0), int2(1, 1), int2(0, 1)};
	int2 at = int2(cell % columns, cell / columns) + offsets[corner];
	// Each row lies on its own world lattice: z snapped to its spacing, x
	// to a column width that covers the view at that distance.
	float row = float(at.y);
	float ahead = landRow(row, float(rows));
	float spacing = landRow(row + 1.0, float(rows)) - ahead;
	float z = floor((cam.eye.z + ahead) / spacing) * spacing;
	float halfWidth = 3.0 + ahead * 1.45;
	float column = 2.0 * halfWidth / float(columns);
	float x = (floor(cam.eye.x / column) + float(at.x) - float(columns) * 0.5) * column;
	float h = landHeight(float2(x, z));
	float e = max(column * 0.5, 0.04);
	float3 normal = normalize(float3(landHeight(float2(x - e, z)) - landHeight(float2(x + e, z)), 2.0 * e,
		landHeight(float2(x, z - e)) - landHeight(float2(x, z + e))));
	LandVertex out;
	out.world = float3(x, h, z);
	out.normal = normal;
	out.position = cameraClip(out.world, f, cam);
	return out;
}

fragment float4 landscapeTerrainFragment(LandVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float3 n = normalize(in.normal);
	float h = in.world.y;
	float slope = 1.0 - n.y;
	float grain = noise(in.world.xz * 3.0);
	// Sand at the shore, meadow in the valley, rock on steep faces, snow on
	// the peaks.
	float3 colour = mix(float3(0.62, 0.52, 0.36), float3(0.16, 0.3, 0.1), smoothstep(0.05, 0.3, h));
	colour = mix(colour, float3(0.2, 0.22, 0.14), smoothstep(0.8, 1.6, h) * 0.6);
	colour = mix(colour, float3(0.36, 0.31, 0.28) * (0.8 + 0.4 * grain), smoothstep(0.35, 0.6, slope));
	colour = mix(colour, float3(0.95, 0.95, 1.0), smoothstep(2.3, 2.7, h + grain * 0.3) * smoothstep(0.6, 0.35, slope));
	float3 sun = landSun(f);
	float lit = saturate(dot(n, sun));
	float3 light = float3(1.0, 0.72, 0.45) * lit * 1.5 + float3(0.25, 0.3, 0.45) * (0.35 + 0.35 * n.y);
	return float4(landFog(colour * light, in.world, cam, f), 1.0);
}

// ---- Water: one plane from under the camera to the far rows.

struct LandWater {
	float4 position [[position]];
	float3 world;
};

vertex LandWater landscapeWaterVertex(uint vid [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float2 corners[6] = {float2(-1, 0), float2(1, 0), float2(-1, 1), float2(1, 0), float2(1, 1), float2(-1, 1)};
	float2 c = corners[vid];
	LandWater out;
	out.world = float3(cam.eye.x + c.x * LAND_FAR * 1.6, 0.0, cam.eye.z - 1.0 + c.y * LAND_FAR);
	out.position = cameraClip(out.world, f, cam);
	return out;
}

static float landWaves(float2 p, const thread Frame &f) {
	float t = f.t * 0.6;
	return fbm(p * 1.6 + float2(t, t * 0.4), 3) + 0.5 * noise(p * 6.0 - float2(t * 1.7, 0.0));
}

fragment float4 landscapeWaterFragment(LandWater in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	Camera cam = landCamera(f);
	float3 view = normalize(in.world - cam.eye);
	// Ripples from the wave field's slope, choppier with the highs.
	float e = 0.03;
	float2 p = in.world.xz;
	float w = landWaves(p, f);
	float chop = 0.12 + 0.25 * f.high * f.presence;
	float3 n = normalize(float3((w - landWaves(p + float2(e, 0.0), f)) * chop / e * 0.1, 1.0,
		(w - landWaves(p + float2(0.0, e), f)) * chop / e * 0.1));
	float3 r = reflect(view, n);
	r.y = abs(r.y);
	float fresnel = 0.03 + 0.97 * pow(1.0 - saturate(-dot(view, n)), 5.0);
	float3 deep = float3(0.02, 0.07, 0.09);
	float3 colour = mix(deep, landSky(r, in.world, f, true), fresnel);
	// The sun's glitter path, flaring on the kick.
	float3 sun = landSun(f);
	colour += float3(1.0, 0.8, 0.55) * pow(saturate(dot(r, sun)), 400.0) * (5.0 + 6.0 * f.kick * f.presence);
	return float4(landFog(colour, in.world, cam, f), 1.0);
}

// ---- Cloud banks: soft sunlit puffs on a world grid ahead, drawn far to
// near so their premultiplied layers stack in order.

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
	int count = int(params[0]);
	float2 corners[6] = {float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, -1), float2(1, 1), float2(-1, 1)};
	float2 c = corners[vid];
	float id = floor(cam.eye.z / LAND_BANK_SPACING) + float(count - int(iid));
	float z = id * LAND_BANK_SPACING;
	float h1 = hash21(float2(id, 1.7)), h2 = hash21(float2(id, 8.3)), h3 = hash21(float2(id, 4.1));
	float3 centre = float3(landPath(z) + (h1 - 0.5) * 22.0, 2.8 + h2 * 2.2, z);
	float radius = 1.6 + 2.2 * h3;
	float3 v = cameraView(centre, cam);
	LandCloud out;
	out.position = viewClip(float3(v.xy + c * radius * float2(1.8, 0.8), v.z), f, cam);
	out.local = c;
	// Gone as they pass overhead, and faded into the haze far away.
	out.fade = smoothstep(1.5, 6.0, v.z) * smoothstep(LAND_BANK_SPACING * float(count), LAND_BANK_SPACING * float(count) * 0.6, v.z)
		* step(0.35, hash21(float2(id, 2.2)));
	out.seed = h1 * 17.0;
	return out;
}

fragment float4 landscapeCloudFragment(LandCloud in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f = frameOf(inputs);
	float2 p = in.local;
	float shape = fbm(p * 1.6 + in.seed + f.t * 0.02, 4);
	float density = saturate((1.0 - dot(p, p)) * 1.4 + shape - 0.9) * in.fade;
	if (density <= 0.0) discard_fragment();
	float lightSide = saturate(0.5 - p.y * 0.4 + shape * 0.4);
	float3 colour = mix(float3(0.5, 0.42, 0.52), float3(1.0, 0.78, 0.58), lightSide);
	float alpha = density * 0.8;
	return float4(colour * alpha, alpha);
}
