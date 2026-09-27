// Drum & bass visualizer: a mirrored neon spectrum standing on a synthwave
// horizon, reflected in a moving perspective grid under an aurora sky.
// `inputs.values` layout is written by apps/dnb/models/Visuals.lua:
//   0 level (RMS)      1 kick pulse     2 track hue      3 section intensity
//   4 section progress 5 beat phase     6 presence (0 idle … 1 playing)
//   7 band count N     8 … 8+N-1 band levels      8+N … 8+2N-1 peak holds

constant float TAU = 6.2831853;
constant float HORIZON = 0.64;   // fraction of the height where bars stand
constant float BAR_SPAN = 0.47;  // half-width covered by the mirrored bars
constant float BAR_HEIGHT = 0.46;

static float3 neon(float t) {
	// Cosine palette sweeping magenta → violet → cyan → amber.
	return 0.55 + 0.45 * cos(TAU * (t + float3(0.0, 0.33, 0.67)));
}

static float hash21(float2 p) {
	p = fract(p * float2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

static float roundBox(float2 p, float2 extent, float r) {
	float2 q = abs(p) - extent + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float band(constant ShaderInputs &inputs, int i, int n, float idle, float t) {
	float v = inputs.values[8 + clamp(i, 0, n - 1)];
	float breathe = idle * (0.05 + 0.035 * sin(t * 1.7 + float(i) * 0.55));
	return max(v, breathe);
}

// Colour and coverage of the spectrum at `p` (x centred on 0, y up from the
// horizon, both in height units).
static float4 spectrum(constant ShaderInputs &inputs, float2 p, float aspect, float hue, float kick, float t) {
	int n = max(int(inputs.values[7]), 1);
	float idle = 1.0 - inputs.values[6];
	float span = BAR_SPAN * aspect;
	float slot = span / float(n);
	float ax = abs(p.x);
	int centre = int(floor(ax / slot));
	float3 colour = float3(0.0);
	float alpha = 0.0;
	for (int k = -1; k <= 1; k++) {
		int i = centre + k;
		if (i < 0 || i >= n) continue;
		float level = band(inputs, i, n, idle, t);
		float h = max(level * BAR_HEIGHT * (1.0 + 0.12 * kick), 0.004);
		float2 c = float2((float(i) + 0.5) * slot, h * 0.5);
		float d = roundBox(float2(ax, p.y) - c, float2(slot * 0.34, h * 0.5), slot * 0.3);
		float heat = clamp(p.y / BAR_HEIGHT, 0.0, 1.0);
		float3 tint = neon(hue + 0.55 * float(i) / float(n) + 0.25 * heat);
		tint = mix(tint, float3(1.0, 0.95, 0.9), smoothstep(0.55, 1.0, heat) * level * 0.7);
		float body = smoothstep(0.0015, -0.0015, d);
		float glow = exp(-max(d, 0.0) * 55.0) * (0.35 + 0.65 * level) * (0.55 + 0.6 * kick);
		colour += tint * (body * 1.15 + glow * 0.55);
		alpha = max(alpha, max(body, glow * 0.6));
		// Peak cap: a thin bright line that falls back after holding.
		float peak = max(inputs.values[8 + n + i] * BAR_HEIGHT * (1.0 + 0.12 * kick), 0.0);
		float capD = roundBox(float2(ax, p.y) - float2(c.x, peak + 0.012), float2(slot * 0.34, 0.0035), 0.003);
		float cap = smoothstep(0.0015, -0.0015, capD) + exp(-max(capD, 0.0) * 120.0) * 0.4;
		colour += mix(tint, float3(1.0), 0.6) * cap * step(0.01, peak);
		alpha = max(alpha, cap);
	}
	return float4(colour, alpha);
}

fragment float4 visualizer(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	float t = inputs.time;
	float aspect = inputs.size.x / max(inputs.size.y, 1.0);
	float level = inputs.values[0];
	float kick = inputs.values[1];
	float hue = inputs.values[2];
	float intensity = inputs.values[3];
	float beat = inputs.values[5];
	float presence = inputs.values[6];
	float2 uv = in.uv;                            // 0,0 top-left
	float2 p = float2((uv.x - 0.5) * aspect, HORIZON - uv.y); // y up from the horizon

	// Sky: deep indigo with two drifting aurora ribbons.
	float3 colour = mix(float3(0.035, 0.012, 0.075), float3(0.10, 0.02, 0.14), uv.y);
	for (int r = 0; r < 2; r++) {
		float fr = float(r);
		float wave = sin(p.x * (2.2 + fr) + t * (0.23 + 0.1 * fr) + sin(p.x * 1.3 - t * 0.17 + fr) * 1.6);
		float y = 0.26 + 0.07 * fr + 0.06 * wave;
		float ribbon = exp(-pow((p.y - y) * (9.0 - 2.0 * fr), 2.0));
		colour += neon(hue + 0.18 + 0.2 * fr + 0.05 * wave) * ribbon * (0.12 + 0.2 * intensity) * (0.5 + 0.5 * presence + 0.6 * kick);
	}
	// Sun: a banded disc behind the bars that swells on each kick.
	float2 sunP = p - float2(0.0, 0.2);
	float sunR = 0.2 + 0.015 * kick;
	float sun = smoothstep(sunR, sunR - 0.004, length(sunP));
	float bands = step(0.5, fract(sunP.y * 28.0 - t * 0.6)) + step(0.04, sunP.y + 0.02);
	colour += mix(neon(hue + 0.02), neon(hue + 0.3), clamp(sunP.y / sunR * 0.5 + 0.5, 0.0, 1.0)) * sun * min(bands, 1.0) * (0.35 + 0.3 * presence);
	colour += neon(hue + 0.1) * exp(-length(sunP) * 5.0) * (0.12 + 0.3 * kick * presence);

	// Kick shockwave rings expanding from the horizon.
	float ringR = 0.08 + (1.0 - kick) * 0.9;
	float ring = exp(-pow((length(p * float2(1.0, 2.2)) - ringR) * 40.0, 2.0)) * kick * presence;
	colour += neon(hue + 0.45) * ring * 0.6;

	if (p.y < 0.0) {
		// Floor: perspective grid rushing toward the viewer on the beat.
		float depth = 0.12 / max(-p.y, 0.002);
		float speed = t * 1.4 + beat * 0.35;
		float gx = abs(fract(p.x * depth * 1.6) - 0.5);
		float gz = abs(fract(depth - speed) - 0.5);
		float lineW = 0.02 * depth;
		float grid = smoothstep(lineW + 0.04, lineW, 0.5 - gx) + smoothstep(lineW + 0.04, lineW, 0.5 - gz);
		float fade = exp(-depth * 0.18);
		colour = mix(float3(0.02, 0.005, 0.04), colour, 0.25);
		colour += neon(hue + 0.6) * grid * fade * (0.25 + 0.35 * intensity + 0.5 * kick);
		// Reflection of the spectrum on the floor.
		float4 mirror = spectrum(inputs, float2(p.x, -p.y * 1.35), aspect, hue, kick, t);
		colour += mirror.rgb * 0.28 * exp(p.y * 7.0);
	} else {
		float4 bars = spectrum(inputs, p, aspect, hue, kick, t);
		colour = mix(colour, bars.rgb, clamp(bars.a, 0.0, 1.0) * 0.85) + bars.rgb * 0.25;
	}
	// Horizon line.
	colour += neon(hue + 0.05) * exp(-abs(p.y) * 260.0) * (0.6 + 0.8 * level);

	// Finish: soft vignette, fine scanlines and grain for a filmic surface.
	float2 v = uv - 0.5;
	colour *= 1.0 - dot(v, v) * 1.1;
	colour *= 0.94 + 0.06 * sin(uv.y * inputs.size.y * 1.5);
	colour += (hash21(uv * inputs.size + fract(t) * 91.0) - 0.5) * 0.035;
	colour = colour / (1.0 + colour * 0.35); // gentle tone map keeps highlights from clipping
	return float4(max(colour, 0.0), 1.0);
}
