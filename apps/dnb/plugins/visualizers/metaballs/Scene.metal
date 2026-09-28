constant int BALLS = 7;

// Metaballs — seven blobs orbiting on Lissajous paths, each sized by a
// slice of the spectrum, fused into one iridescent surface.
static float3 metaballsScene(constant ShaderInputs &inputs, float2 uv, const thread Frame &f) {
	float2 p = stagePoint(uv, f);
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
