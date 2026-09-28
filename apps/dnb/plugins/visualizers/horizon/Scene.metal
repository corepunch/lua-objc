// The synthwave horizon — mirrored neon spectrum, banded sun, kick rings
// and a perspective grid rushing toward the viewer. The horizon sits a
// quarter of the stage up from its bottom edge, leaving the sky, where the
// sun and bars rise, the larger share; the grid continues under the panels.
constant float HORIZON_Y = -0.25; // stage heights from the stage centre

static float3 horizonScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = stagePoint(uv, f) - float2(0.0, HORIZON_Y);
	float3 colour = sky(uv, p, f);
	float2 sunP = p - float2(0.0, 0.18);
	float sunR = 0.18 + 0.015 * f.kick;
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
