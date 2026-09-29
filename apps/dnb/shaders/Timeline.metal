// The arrangement timeline (models/Timeline.lua): one draw of instanced
// rounded rects into layer 1 (a clip on its channel's row), then the
// finishing pass adds the bar grid, the channels' level meters and the fixed
// playhead. Everything slides right to left: every position is a set bar,
// the playhead advances by its speed times `inputs.age` between updates, so
// the strip scrolls evenly on every display frame.
//
// values: [0] playhead (set bar), [1] bars per second, [2] channel rows,
//         [3] bars in view, [4] bars behind the playhead, [5] display
//         scale (pixels per point), [6…13] each row's meter (0…1),
//         [14…21] each row's colour
// data:   per instance row, first bar, bars, colour (its role), its
//         envelope at its first and last bar and whether it
//         thins from below

// Channel tints by role: the system palette in its dark appearance. Roles
// keep to their family's hue: drums red to pink, bass orange, chords purple
// to indigo, melody cyan to green, texture and effects grey and yellow.
constant float3 TIMELINE_COLOURS[11] = {
	float3(1.000, 0.271, 0.227), // drums: red
	float3(1.000, 0.216, 0.373), // tops: pink
	float3(1.000, 0.624, 0.039), // bass: orange
	float3(0.749, 0.353, 0.949), // pad: purple
	float3(0.369, 0.361, 0.902), // keys: indigo
	float3(0.580, 0.470, 1.000), // stab
	float3(0.353, 0.784, 0.980), // arp: cyan
	float3(0.388, 0.902, 0.886), // lead: mint
	float3(0.188, 0.820, 0.345), // counter: green
	float3(0.557, 0.557, 0.576), // texture: grey
	float3(1.000, 0.839, 0.039), // fx: yellow
};
constant uint TIMELINE_ROWS = 8;
constant uint TIMELINE_METERS = 6;      // where the rows' meters start in the values
constant float TIMELINE_GAP = 1.0;      // points between neighbouring clips
constant float TIMELINE_RADIUS = 3.0;   // clip corner radius in points
constant float TIMELINE_RESTING = 0.6;  // opacity away from the playhead
constant float TIMELINE_PAST = 0.5;     // what has played dims further
constant float TIMELINE_BODY = 0.62;    // a clip's fill
constant float TIMELINE_CUT = 0.3;      // the part of a clip its envelope takes away
constant float TIMELINE_SHEEN = 0.22;   // how far a clip lightens towards its top edge
constant float TIMELINE_SHADE = 0.3;    // and darkens towards its bottom
constant float TIMELINE_DRIFT = 0.12;   // how far its hue turns from first bar to last
constant float TIMELINE_RIM = 0.3;      // the lighter edge around a clip
constant float TIMELINE_GRID = 0.06;    // a bar line's opacity; phrase lines double it
constant float TIMELINE_METER = 0.85;   // a meter's opacity at its playhead end
constant float TIMELINE_METER_HEIGHT = 0.36; // of its row

struct TimelineBlock {
	float4 position [[position]];
	float2 pixel;
	float4 rect [[flat]];   // left, top, right, bottom in pixels
	float3 colour [[flat]];
	float strength [[flat]];
	float3 shape [[flat]];  // envelope at the first and last bar; thins from below
};

static float timelinePlayhead(constant ShaderInputs &inputs) {
	return inputs.values[0] + inputs.values[1] * inputs.age;
}

vertex TimelineBlock timelineBlockVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
		constant ShaderInputs &inputs [[buffer(0)]], constant float *data [[buffer(1)]]) {
	uint at = iid * 7;
	float row = data[at], start = data[at + 1], length = data[at + 2];
	float3 shape = float3(data[at + 4], data[at + 5], data[at + 6]);
	float playhead = timelinePlayhead(inputs);
	float rows = max(inputs.values[2], 1.0), window = inputs.values[3], left = playhead - inputs.values[4];
	float scale = inputs.values[5];
	float2 size = inputs.size;
	float lane = 1.0 / rows;
	float top = row * lane;
	float bottom = top + lane;
	float gap = TIMELINE_GAP * scale * 0.5;
	float4 rect = float4((start - left) / window * size.x + gap, top * size.y + gap,
		(start + length - left) / window * size.x - gap, bottom * size.y - gap);
	const uint corners[6] = {0, 1, 2, 2, 1, 3};
	uint corner = corners[vid];
	float2 p = float2((corner & 1) ? rect.z : rect.x, (corner & 2) ? rect.w : rect.y);
	bool playing = start <= playhead && playhead < start + length;
	TimelineBlock out;
	out.position = float4(p.x / size.x * 2.0 - 1.0, 1.0 - p.y / size.y * 2.0, 0.0, 1.0);
	out.pixel = p;
	out.rect = rect;
	out.colour = TIMELINE_COLOURS[int(data[at + 3])];
	// What is playing brightens; what has played dims.
	out.strength = playing ? 1.0 : (start + length <= playhead ? TIMELINE_RESTING * TIMELINE_PAST : TIMELINE_RESTING);
	out.shape = shape;
	return out;
}

fragment float4 timelineBlockFragment(TimelineBlock in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	float scale = inputs.values[5];
	float2 centre = (in.rect.xy + in.rect.zw) * 0.5;
	float2 extent = max((in.rect.zw - in.rect.xy) * 0.5, float2(0.0));
	float radius = min(TIMELINE_RADIUS * scale, min(extent.x, extent.y));
	float2 q = abs(in.pixel - centre) - extent + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float alpha = saturate(0.5 - d) * in.strength;
	float2 uv = (in.pixel - in.rect.xy) / max(in.rect.zw - in.rect.xy, float2(1.0));
	// Light falls from above: a sheen towards the top edge, shade towards
	// the bottom, and the hue drifting a little along the clip.
	float3 colour = in.colour;
	colour = mix(colour, colour.brg, TIMELINE_DRIFT * uv.x);
	colour = mix(colour, float3(1.0), TIMELINE_SHEEN * (1.0 - smoothstep(0.0, 0.6, uv.y)));
	colour *= 1.0 - TIMELINE_SHADE * smoothstep(0.35, 1.0, uv.y);
	// The envelope: a fade or a low-pass takes the top of the clip away,
	// a high-pass the bottom, and a line rides the edge of what is left.
	float height = max(in.rect.w - in.rect.y, 1.0);
	float opening = mix(in.shape.x, in.shape.y, uv.x);
	bool thins = in.shape.z > 0.5;
	float edge = thins ? opening : 1.0 - opening;
	float fromEdge = (uv.y - edge) * height;
	float kept = thins ? saturate(0.5 - fromEdge) : saturate(0.5 + fromEdge);
	bool shaped = min(in.shape.x, in.shape.y) < 1.0;
	float line = shaped ? saturate(1.0 - abs(fromEdge) / scale) : 0.0;
	float rim = saturate(1.0 + d / scale);
	float body = TIMELINE_BODY * mix(TIMELINE_CUT, 1.0, kept);
	colour = mix(colour, float3(1.0), 0.5 * line);
	alpha *= saturate(body + TIMELINE_RIM * rim + 0.4 * line);
	return float4(colour * alpha, alpha);
}

fragment float4 timeline(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]],
		texture2d<float> blocks [[texture(0)]]) {
	constexpr sampler s(filter::nearest, address::clamp_to_edge);
	float4 colour = blocks.sample(s, in.uv, level(0.0));
	float window = inputs.values[3], behind = inputs.values[4];
	float barsPerPixel = window / inputs.size.x;
	float bar = timelinePlayhead(inputs) - behind + in.uv.x * window;
	// Bar lines under the lanes, stronger on each eight-bar phrase.
	float fromLine = abs(fract(bar + 0.5) - 0.5) / barsPerPixel;
	float phrase = abs(fract(bar / 8.0 + 0.5) - 0.5) * 8.0 / barsPerPixel < 1.0 ? 2.0 : 1.0;
	float grid = saturate(1.0 - fromLine) * TIMELINE_GRID * phrase;
	colour += float4(grid) * (1.0 - colour.a);
	// Each channel's level, as a tracker shows it: a bar in the channel's
	// tint growing back from the playhead over what has already played.
	float rows = max(inputs.values[2], 1.0);
	uint row = min(uint(in.uv.y * rows), TIMELINE_ROWS - 1);
	float level = inputs.values[TIMELINE_METERS + row];
	float along = (behind / window - in.uv.x) / (behind / window);
	float across = abs(fract(in.uv.y * rows) - 0.5);
	if (level > 0.0 && along >= 0.0 && along <= level && across < TIMELINE_METER_HEIGHT * 0.5) {
		float3 tint = TIMELINE_COLOURS[min(int(inputs.values[TIMELINE_METERS + TIMELINE_ROWS + row]), 10)];
		float glow = TIMELINE_METER * (1.0 - 0.6 * along / max(level, 0.001));
		colour = mix(colour, float4(mix(tint, float3(1.0), 0.35), 1.0), glow);
	}
	// The fixed playhead.
	float head = saturate(1.5 * inputs.values[5] - abs(in.uv.x - behind / window) * inputs.size.x);
	return mix(colour, float4(1.0), head * 0.9);
}
