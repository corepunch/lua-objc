// Drum & bass visualizer: six audio-reactive scenes that crossfade at
// section and phrase changes — a synthwave spectrum horizon, a flight over
// layered ridges, metaballs, light trails, a tunnel and a kaleidoscope of
// crystal cells.
// `inputs.values` layout is written by apps/dnb/models/Visuals.lua:
//   0 level (RMS)      1 kick pulse     2 track hue      3 section intensity
//   4 section progress 5 beat phase     6 presence (0 idle … 1 playing)
//   7 band count N     8 scene          9 next scene     10 crossfade 0…1
//   11 snare pulse     12 low bands     13 high bands    14 travel   15 bar phase
//   16 … 16+N-1 band levels             16+N … 16+2N-1 peak holds

constant float TAU = 6.2831853;
constant int HEADER = 16;
constant float HORIZON = 0.64;   // fraction of the height where bars stand
constant float BAR_SPAN = 0.47;  // half-width covered by the mirrored bars
constant float BAR_HEIGHT = 0.46;
constant int RIDGES = 6;         // landscape layers, far to near
constant int BALLS = 7;
constant int TRAILS = 9;
constant int TRAIL_SEGMENTS = 28;
constant float TRAIL_SPAN = 1.6; // travel covered by one trail

struct Frame {
	float t, aspect, level, kick, hue, intensity, beat, presence, snare, low, high, travel, phase;
	int n;
};

static float3 neon(float t) {
	// Cosine palette sweeping magenta → violet → cyan → amber.
	return 0.55 + 0.45 * cos(TAU * (t + float3(0.0, 0.33, 0.67)));
}

static float hash21(float2 p) {
	p = fract(p * float2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
	float n = hash21(p);
	return float2(n, hash21(p + n + 17.0));
}

static float noise(float2 p) {
	float2 i = floor(p), f = fract(p);
	float2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
		mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

static float ridgeNoise(float x, float seed) {
	float v = 0.0, a = 0.5, f = 1.0;
	for (int o = 0; o < 4; o++) {
		v += a * (1.0 - abs(noise(float2(x * f, seed + float(o) * 7.1)) * 2.0 - 1.0));
		f *= 2.1;
		a *= 0.5;
	}
	return v;
}

static float roundBox(float2 p, float2 extent, float r) {
	float2 q = abs(p) - extent + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float segment(float2 p, float2 a, float2 b) {
	float2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

static float band(constant ShaderInputs &inputs, int i, int n, float idle, float t) {
	float v = inputs.values[HEADER + clamp(i, 0, n - 1)];
	float breathe = idle * (0.05 + 0.035 * sin(t * 1.7 + float(i) * 0.55));
	return max(v, breathe);
}

// Band level at a 0…1 position across the spectrum, interpolated.
static float spectrumAt(constant ShaderInputs &inputs, float x, const thread Frame &f) {
	float idle = 1.0 - f.presence;
	float s = clamp(x, 0.0, 1.0) * float(f.n - 1);
	int i = int(floor(s));
	return mix(band(inputs, i, f.n, idle, f.t), band(inputs, i + 1, f.n, idle, f.t), fract(s));
}

// Colour and coverage of the spectrum at `p` (x centred on 0, y up from the
// horizon, both in height units).
static float4 spectrumBars(constant ShaderInputs &inputs, float2 p, const thread Frame &f) {
	int n = f.n;
	float idle = 1.0 - f.presence;
	float span = BAR_SPAN * f.aspect;
	float slot = span / float(n);
	float ax = abs(p.x);
	int centre = int(floor(ax / slot));
	float3 colour = float3(0.0);
	float alpha = 0.0;
	for (int k = -1; k <= 1; k++) {
		int i = centre + k;
		if (i < 0 || i >= n) continue;
		float level = band(inputs, i, n, idle, f.t);
		float h = max(level * BAR_HEIGHT * (1.0 + 0.12 * f.kick), 0.004);
		float2 c = float2((float(i) + 0.5) * slot, h * 0.5);
		float d = roundBox(float2(ax, p.y) - c, float2(slot * 0.34, h * 0.5), slot * 0.3);
		float heat = clamp(p.y / BAR_HEIGHT, 0.0, 1.0);
		float3 tint = neon(f.hue + 0.55 * float(i) / float(n) + 0.25 * heat);
		tint = mix(tint, float3(1.0, 0.95, 0.9), smoothstep(0.55, 1.0, heat) * level * 0.7);
		float body = smoothstep(0.0015, -0.0015, d);
		float glow = exp(-max(d, 0.0) * 55.0) * (0.35 + 0.65 * level) * (0.55 + 0.6 * f.kick);
		colour += tint * (body * 1.15 + glow * 0.55);
		alpha = max(alpha, max(body, glow * 0.6));
		// Peak cap: a thin bright line that falls back after holding.
		float peak = max(inputs.values[HEADER + n + i] * BAR_HEIGHT * (1.0 + 0.12 * f.kick), 0.0);
		float capD = roundBox(float2(ax, p.y) - float2(c.x, peak + 0.012), float2(slot * 0.34, 0.0035), 0.003);
		float cap = smoothstep(0.0015, -0.0015, capD) + exp(-max(capD, 0.0) * 120.0) * 0.4;
		colour += mix(tint, float3(1.0), 0.6) * cap * step(0.01, peak);
		alpha = max(alpha, cap);
	}
	return float4(colour, alpha);
}

static float3 sky(float2 uv, float2 p, const thread Frame &f) {
	float3 colour = mix(float3(0.035, 0.012, 0.075), float3(0.10, 0.02, 0.14), uv.y);
	for (int r = 0; r < 2; r++) {
		float fr = float(r);
		float wave = sin(p.x * (2.2 + fr) + f.t * (0.23 + 0.1 * fr) + sin(p.x * 1.3 - f.t * 0.17 + fr) * 1.6);
		float y = 0.26 + 0.07 * fr + 0.06 * wave;
		float ribbon = exp(-pow((p.y - y) * (9.0 - 2.0 * fr), 2.0));
		colour += neon(f.hue + 0.18 + 0.2 * fr + 0.05 * wave) * ribbon * (0.12 + 0.2 * f.intensity)
			* (0.5 + 0.5 * f.presence + 0.6 * f.kick);
	}
	return colour;
}

// 0: the synthwave horizon — mirrored neon spectrum, banded sun, kick rings
// and a perspective grid rushing toward the viewer.
static float3 horizonScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, HORIZON - uv.y);
	float3 colour = sky(uv, p, f);
	float2 sunP = p - float2(0.0, 0.2);
	float sunR = 0.2 + 0.015 * f.kick;
	float sun = smoothstep(sunR, sunR - 0.004, length(sunP));
	float bands = step(0.5, fract(sunP.y * 28.0 - f.t * 0.6)) + step(0.04, sunP.y + 0.02);
	colour += mix(neon(f.hue + 0.02), neon(f.hue + 0.3), clamp(sunP.y / sunR * 0.5 + 0.5, 0.0, 1.0))
		* sun * min(bands, 1.0) * (0.35 + 0.3 * f.presence);
	colour += neon(f.hue + 0.1) * exp(-length(sunP) * 5.0) * (0.12 + 0.3 * f.kick * f.presence);
	float ringR = 0.08 + (1.0 - f.kick) * 0.9;
	float ring = exp(-pow((length(p * float2(1.0, 2.2)) - ringR) * 40.0, 2.0)) * f.kick * f.presence;
	colour += neon(f.hue + 0.45) * ring * 0.6;
	if (p.y < 0.0) {
		float depth = 0.12 / max(-p.y, 0.002);
		float speed = f.t * 1.4 + f.beat * 0.35;
		float gx = abs(fract(p.x * depth * 1.6) - 0.5);
		float gz = abs(fract(depth - speed) - 0.5);
		float lineW = 0.02 * depth;
		float grid = smoothstep(lineW + 0.04, lineW, 0.5 - gx) + smoothstep(lineW + 0.04, lineW, 0.5 - gz);
		colour = mix(float3(0.02, 0.005, 0.04), colour, 0.25);
		colour += neon(f.hue + 0.6) * grid * exp(-depth * 0.18) * (0.25 + 0.35 * f.intensity + 0.5 * f.kick);
		float4 mirror = spectrumBars(inputs, float2(p.x, -p.y * 1.35), f);
		colour += mirror.rgb * 0.28 * exp(p.y * 7.0);
	} else {
		float4 bars = spectrumBars(inputs, p, f);
		colour = mix(colour, bars.rgb, clamp(bars.a, 0.0, 1.0) * 0.85) + bars.rgb * 0.25;
	}
	colour += neon(f.hue + 0.05) * exp(-abs(p.y) * 260.0) * (0.6 + 0.8 * f.level);
	return colour;
}

// 1: a night flight over layered ridges. Far layers drift slowly behind
// fog; the nearest ones rush past and their peaks rise with the spectrum.
static float3 landscapeScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 1.0 - uv.y); // y up from the bottom
	// Dusk sky: indigo overhead, a neon glow along the far ridges.
	float3 glow = neon(f.hue + 0.05);
	float3 colour = mix(glow * 0.55, float3(0.03, 0.01, 0.08), smoothstep(0.35, 1.0, p.y));
	// Stars: one point per cell, twinkling, only where the sky is dark.
	float2 grid = uv * float2(f.aspect, 1.0) * 70.0;
	float2 cell = floor(grid);
	float2 spot = hash22(cell) * 0.8 + 0.1;
	float star = smoothstep(0.09, 0.0, length(fract(grid) - spot)) * step(0.8, hash21(cell + 5.3));
	colour += star * (0.5 + 0.5 * sin(f.t * 3.0 + hash21(cell + 3.1) * TAU)) * smoothstep(0.5, 0.85, p.y);
	// A low moon that pulses with the kick.
	float2 moon = p - float2(0.28 * f.aspect, 0.66);
	float3 moonColour = mix(glow, float3(1.0), 0.55);
	colour += moonColour * (smoothstep(0.07, 0.066, length(moon)) * 0.8
		+ exp(-length(moon) * 8.0) * (0.2 + 0.35 * f.kick));
	float3 fog = glow * 0.42;
	for (int i = 0; i < RIDGES; i++) {
		float fi = float(i);
		float near = fi / float(RIDGES - 1);
		float scale = 0.7 + 1.4 * (1.0 - near);
		float x = p.x * scale + f.travel * (0.3 + 2.6 * near * near) + fi * 11.3;
		float base = 0.5 - 0.085 * fi;
		float height = base + (0.16 + 0.16 * near) * ridgeNoise(x * 0.9, fi * 3.7) - 0.08;
		// The nearest ridges carry the spectrum on their crests.
		height += spectrumAt(inputs, fract(abs(x) * 0.07), f) * 0.1 * near * near * (1.0 + 0.3 * f.kick);
		if (p.y < height) {
			// Atmospheric perspective: far ridges dissolve into the glow.
			float3 body = mix(float3(0.035, 0.012, 0.06), fog, pow(1.0 - near, 1.4) * 0.85);
			body *= 1.0 - 0.5 * smoothstep(0.0, 0.25, height - p.y) * near;
			float rim = exp(-(height - p.y) * (50.0 + 120.0 * near));
			colour = body + neon(f.hue + 0.35 + 0.08 * fi) * rim * (0.2 + 0.7 * near) * (0.6 + 0.6 * f.level + 0.5 * f.kick);
		}
	}
	// Ground mist rising with the bass.
	colour += fog * exp(-p.y * 10.0) * (0.25 + 0.5 * f.low);
	return colour;
}

// 2: metaballs — seven blobs orbiting on Lissajous paths, each sized by a
// slice of the spectrum, fused into one iridescent surface.
static float3 metaballScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 0.5 - uv.y);
	float field = 0.0;
	float2 gradient = float2(0.0);
	float3 tint = float3(0.0);
	for (int i = 0; i < BALLS; i++) {
		float fi = float(i);
		float s = f.travel * (0.35 + 0.07 * fi) + fi * 1.9;
		float2 c = float2(sin(s * 1.3 + fi) * 0.36 * f.aspect, sin(s * 1.7 + fi * 2.3) * 0.28);
		float r = 0.07 + 0.09 * spectrumAt(inputs, (fi + 0.5) / float(BALLS), f) + 0.03 * f.kick;
		float2 d = p - c;
		float d2 = max(dot(d, d), 1e-5);
		float w = r * r / d2;
		field += w;
		gradient -= 2.0 * w / d2 * d; // analytic ∇(r²/|d|²)
		tint += neon(f.hue + fi / float(BALLS) * 0.6) * w;
	}
	tint /= max(field, 1e-4);
	float3 colour = float3(0.02, 0.008, 0.05) + neon(f.hue + 0.7) * 0.05 * (1.0 - length(p));
	// Shade the iso-surface as liquid chrome: a normal from the field's
	// gradient, a key light from the upper left and a hot specular.
	// ∇(−1/field) flattens toward each centre, so the blobs read as domes.
	float3 normal = normalize(float3(-gradient * 0.05 / (field * field), 1.0));
	float3 light = normalize(float3(-0.5, 0.6, 0.8));
	float diffuse = max(dot(normal, light), 0.0);
	float specular = pow(max(dot(reflect(-light, normal), float3(0, 0, 1)), 0.0), 24.0);
	float surface = smoothstep(0.97, 1.03, field);
	float3 body = tint * (0.25 + 0.85 * diffuse) + float3(1.0) * specular * (0.6 + 0.6 * f.snare);
	colour = mix(colour, body, surface);
	float halo = smoothstep(0.25, 1.0, field) * (1.0 - surface);
	colour += tint * halo * (0.3 + 0.5 * f.level);
	colour += mix(tint, float3(1.0), 0.5) * exp(-pow((field - 1.0) * 6.0, 2.0)) * (0.3 + 0.6 * f.kick);
	return colour;
}

// 3: light trails — ribbons tracing rose curves, their length set by the
// travelled distance so they stretch as the music gets louder.
static float3 trailsScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 0.5 - uv.y);
	float3 colour = float3(0.015, 0.006, 0.04);
	for (int i = 0; i < TRAILS; i++) {
		float fi = float(i);
		float k = 2.0 + fmod(fi, 3.0);
		float amp = 0.32 + 0.12 * spectrumAt(inputs, fi / float(TRAILS), f);
		float3 tint = neon(f.hue + fi / float(TRAILS) * 0.7);
		float glow = 0.0;
		float2 prev = float2(0.0);
		for (int j = 0; j <= TRAIL_SEGMENTS; j++) {
			float s = f.travel * (1.2 + 0.15 * fi) + fi * 0.8 - float(j) * TRAIL_SPAN / float(TRAIL_SEGMENTS);
			float r = amp * (0.35 + 0.65 * cos(k * s * 0.5));
			float2 q = float2(r * cos(s * 0.5 + fi) * f.aspect * 0.8, r * sin(s * 0.5 + fi));
			if (j > 0) {
				float fade = 1.0 - float(j) / float(TRAIL_SEGMENTS);
				float d = segment(p, prev, q);
				// A hot core inside a soft inverse-square halo.
				glow += fade * fade * (0.00012 / (d * d + 0.0004) + smoothstep(0.006 * fade + 0.001, 0.0, d) * 1.2);
			}
			prev = q;
		}
		colour += tint * glow * (0.45 + 0.5 * f.level + 0.6 * f.snare);
	}
	return colour;
}

// 4: tunnel — rings rushing past on the beat, the spectrum wrapped around
// the walls and the whole bore twisting with the bar.
static float3 tunnelScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 0.5 - uv.y);
	p += 0.04 * float2(sin(f.t * 0.7), cos(f.t * 0.5));
	float r = max(length(p), 1e-3);
	float a = atan2(p.y, p.x) / TAU + 0.5 + 0.08 * sin(f.phase * TAU) + f.t * 0.02;
	// Mirrored around the bore so there is no seam where the angle wraps.
	float around = abs(fract(a * 2.0) * 2.0 - 1.0);
	float depth = 0.25 / r + f.travel * 2.5;
	float wall = spectrumAt(inputs, around, f);
	float rings = pow(abs(sin(depth * TAU * 0.5)), 16.0);
	float spokes = pow(abs(sin(around * TAU * 6.0)), 30.0);
	float fade = smoothstep(0.0, 0.3, r) * exp(-r * 0.6);
	float3 tint = neon(f.hue + depth * 0.04 + around * 0.25);
	float3 colour = float3(0.015, 0.005, 0.04);
	colour += tint * rings * (0.5 + 1.2 * f.kick + 0.6 * wall) * fade;
	colour += tint * spokes * wall * 0.9 * fade;
	colour += tint * wall * smoothstep(0.3, 1.0, r) * 0.18;
	colour += neon(f.hue + 0.5) * exp(-r * 14.0) * (0.3 + 0.9 * f.kick); // the light at the end
	return colour;
}

// 5: crystals — a six-fold kaleidoscope of drifting Voronoi cells whose
// facets light with their slice of the spectrum.
static float3 crystalScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = float2((uv.x - 0.5) * f.aspect, 0.5 - uv.y);
	float angle = atan2(p.y, p.x) + f.travel * 0.2;
	float sector = TAU / 6.0;
	angle = abs(fmod(angle + TAU * 8.0, sector) - sector * 0.5);
	float2 q = float2(cos(angle), sin(angle)) * length(p) * 5.0 + float2(f.travel * 0.6, 0.0);
	float2 cell = floor(q);
	float first = 8.0, second = 8.0;
	float2 id = float2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float2 c = cell + float2(x, y);
			float2 o = hash22(c);
			o = 0.5 + 0.4 * sin(f.t * 0.6 + o * TAU);
			float d = length(c + o - q);
			if (d < first) { second = first; first = d; id = c; }
			else if (d < second) second = d;
		}
	}
	float h = hash21(id);
	float level = spectrumAt(inputs, h, f);
	float edge = exp(-(second - first) * 30.0);
	float3 tint = neon(f.hue + h * 0.5);
	float3 colour = float3(0.02, 0.008, 0.05);
	// Facets glow from the centre like cut gems, bright with their band.
	colour += tint * (0.08 + level * 1.1) * pow(clamp(1.0 - first, 0.0, 1.0), 1.5);
	colour += mix(tint, float3(1.0), 0.5) * edge * (0.5 + 0.8 * f.high + 0.6 * f.kick);
	colour += tint * step(0.93, h) * f.snare * 0.8; // snare hits flash single facets
	return colour * (1.0 - smoothstep(0.4, 0.9, length(p)) * 0.6);
}

static float3 scene(int index, constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	switch (index) {
		case 1: return landscapeScene(inputs, uv, f);
		case 2: return metaballScene(inputs, uv, f);
		case 3: return trailsScene(inputs, uv, f);
		case 4: return tunnelScene(inputs, uv, f);
		case 5: return crystalScene(inputs, uv, f);
		default: return horizonScene(inputs, uv, f);
	}
}

fragment float4 visualizer(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	Frame f;
	f.t = inputs.time;
	f.aspect = inputs.size.x / max(inputs.size.y, 1.0);
	f.level = inputs.values[0];
	f.kick = inputs.values[1];
	f.hue = inputs.values[2];
	f.intensity = inputs.values[3];
	f.beat = inputs.values[5];
	f.presence = inputs.values[6];
	f.n = max(int(inputs.values[7]), 2);
	f.snare = inputs.values[11];
	f.low = inputs.values[12];
	f.high = inputs.values[13];
	f.travel = inputs.values[14];
	f.phase = inputs.values[15];
	float2 uv = in.uv; // 0,0 top-left

	float fade = inputs.values[10];
	float3 colour = scene(int(inputs.values[8]), inputs, uv, f);
	if (fade > 0.0) {
		// Crossfade through a brief bloom so the cut reads as a transition.
		float w = smoothstep(0.0, 1.0, fade);
		colour = mix(colour, scene(int(inputs.values[9]), inputs, uv, f), w) * (1.0 + 0.6 * sin(w * 3.14159));
	}

	// Finish: soft vignette, fine scanlines and grain for a filmic surface.
	float2 v = uv - 0.5;
	colour *= 1.0 - dot(v, v) * 1.1;
	colour *= 0.94 + 0.06 * sin(uv.y * inputs.size.y * 1.5);
	colour += (hash21(uv * inputs.size + fract(f.t) * 91.0) - 0.5) * 0.035;
	colour = colour / (1.0 + colour * 0.35); // gentle tone map keeps highlights from clipping
	return float4(max(colour, 0.0), 1.0);
}
