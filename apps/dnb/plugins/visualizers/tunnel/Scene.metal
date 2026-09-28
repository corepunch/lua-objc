// Tunnel — rings rushing past on the beat, the spectrum wrapped around
// the walls and the whole bore twisting with the bar.
static float3 tunnelScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = stagePoint(uv, f);
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
