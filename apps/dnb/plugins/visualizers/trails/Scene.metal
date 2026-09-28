constant float TRAIL_SPAN = 1.6;      // travel covered by one trail
constant float TRAIL_SAMPLES = 28.0;  // the glow is calibrated to this many segments per trail
constant float TRAIL_WIDTH = 0.2;     // ribbon half-width, stage heights; the halo ends here
constant float TRAIL_HALO = 0.00012;  // inverse-square halo strength per segment…
constant float TRAIL_SOFT = 0.0004;   // …and its softening near the line
constant float TRAIL_REACH = 0.3;     // longest stretch of curve treated as one straight line

struct TrailVertex {
	float4 position [[position]];
	float across;  // signed distance from the curve, stage heights
	float beyond;  // distance past the head, on its cap
	float width;   // this ribbon's half-width here
	float fade;    // 1 at the head … 0 at the tail
	float spacing; // curve length per calibration segment here
	float reach;   // length of curve near here that is close to straight
	float3 tint;
};

// A rose curve: radius swinging with k petals while the direction turns,
// stretched across the stage.
static float2 trailPoint(float s, float k, float amp, float fi, const thread Frame &f) {
	float r = amp * (0.35 + 0.65 * cos(k * s * 0.5));
	return float2(r * cos(s * 0.5 + fi) * f.aspect * 0.8, r * sin(s * 0.5 + fi));
}

fragment float4 trailsBackground(ShaderVertex in [[stage_in]]) {
	return float4(0.015, 0.006, 0.04, 1.0);
}

// Light trails — ribbons tracing rose curves, their length set by the
// travelled distance so they stretch as the music gets louder. Each trail is
// a ribbon of quads along its curve (instance = trail): sample pair 0 caps
// the head, pair j + 1 sits at sample j, and the fragment turns the
// distance across the ribbon into the glow.
vertex TrailVertex trailsVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]], constant float *params [[buffer(2)]]) {
	Frame f = frameOf(inputs);
	int points = int(params[0]);
	float fi = float(iid);
	float k = 2.0 + fmod(fi, 3.0);
	float amp = 0.32 + 0.12 * spectrumAt(inputs, fi / 9.0, f);
	// Two triangles per segment between sample pairs `segment` and `segment + 1`.
	int corner = int(vid % 6);
	int pair = int(vid / 6) + ((corner == 2 || corner == 4 || corner == 5) ? 1 : 0);
	float side = (corner == 1 || corner == 3 || corner == 4) ? 1.0 : -1.0;
	int j = max(pair - 1, 0);
	float along = float(j) / float(points - 1);
	float head = f.travel * (1.2 + 0.15 * fi) + fi * 0.8;
	float s = head - along * TRAIL_SPAN;
	float ds = TRAIL_SPAN / float(points - 1) * 0.5;
	float2 q = trailPoint(s, k, amp, fi, f);
	float2 after = trailPoint(s + ds, k, amp, fi, f), before = trailPoint(s - ds, k, amp, fi, f);
	float2 tangent = (after - before) / (2.0 * ds);
	float2 bend = (after - 2.0 * q + before) / (ds * ds);
	float speed = max(length(tangent), 1e-4);
	// A ribbon wider than the curve's radius folds over itself on the inside
	// of the bend, adding its light twice; tight loops get a narrower one.
	float radius = speed * speed * speed / max(abs(tangent.x * bend.y - tangent.y * bend.x), 1e-5);
	float2 dir = tangent / speed;
	float2 normal = float2(-dir.y, dir.x);

	TrailVertex out;
	out.fade = 1.0 - along;
	out.width = min(TRAIL_WIDTH * (0.35 + 0.65 * out.fade), radius * 0.9);
	out.across = side * out.width;
	out.beyond = 0.0;
	if (pair == 0) {
		// The cap: the head's halo runs on past its end.
		q += dir * out.width;
		out.beyond = out.width;
	}
	out.position = stageClip(q + normal * out.across, f);
	out.spacing = speed * TRAIL_SPAN / TRAIL_SAMPLES;
	out.reach = min(radius, TRAIL_REACH);
	out.tint = neon(f.hue + fi / 9.0 * 0.7) * (0.45 + 0.5 * f.level + 0.6 * f.snare);
	return out;
}

fragment float4 trailsFragment(TrailVertex in [[stage_in]]) {
	float d = length(float2(in.across, in.beyond));
	// The halo of densely spaced segments, H/(d² + c) each, summed along a
	// straight stretch of length L centred here: 2H·atan(L / 2D) / (spacing·D)
	// with D = √(d² + c). Close to the line that is the old per-pixel sum's
	// πH / (spacing·D); farther out it falls off as the stretch's inverse
	// square instead of lighting the whole ribbon where the curve is slow.
	// Eased to zero at the ribbon's edge.
	float edge = saturate(1.0 - d * d / (in.width * in.width));
	float D = sqrt(d * d + TRAIL_SOFT);
	float halo = 2.0 * TRAIL_HALO * atan(in.reach / (2.0 * D)) / (max(in.spacing, 1e-3) * D) * edge * edge;
	// A hot core inside it.
	float core = smoothstep(0.006 * in.fade + 0.001, 0.0, d) * 1.2;
	return float4(in.tint * in.fade * in.fade * (halo + core), 0.0);
}
