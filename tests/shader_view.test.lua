_G.__headless = true
local ns = require("AppKit")
local xml = require("ui.xml")
local t = require("TestKit")

local dir = assert(io.popen("/usr/bin/mktemp -d /private/tmp/shader-view.XXXXXXXX")):read("*l")
local function write(name, text)
	local path = dir .. "/" .. name
	local file = assert(io.open(path, "w"))
	file:write(text)
	file:close()
	return path
end

local good = write("good.metal", [==[
fragment float4 glow(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	return float4(in.uv, inputs.values[0] + sin(inputs.time), 1.0);
}
]==])
local view = ns.ShaderView({source = good, ["function"] = "glow", values = {0.25, 0.5}})
t.expect(view ~= nil, "ShaderView compiles app Metal source against the shared inputs")
t.assertEqual(#view.values, 2, "initial values reach the shader")
t.assertEqual(view.values[2], 0.5, "values keep their order")
view.values = {1, 2, 3}
t.assertEqual(#view.values, 3, "assigning values replaces them")
t.expect(view.fillWidth and view.fillHeight, "a shader fills its proposal like a gradient")
t.assertEqual(view.isPaused, true, "the runtime display link, not MTKView's timer, drives drawing")
local bridge = require("AppKitNative")
local ms = bridge._shaderFrameTime(view, 64, 48)
t.expect(type(ms) == "number" and ms >= 0, "a frame can be timed offscreen at any pixel size")
t.assertThrows(function() bridge._shaderFrameTime(view, 0, 48) end, "frame timing needs a positive size")
t.assertThrows(function() bridge._shaderFrameTime(ns.VStack({}), 64, 48) end, "only shader views are timed")

local bad = write("bad.metal", "fragment float4 broken( { }\n")
local ok, err = pcall(ns.ShaderView, {source = bad, ["function"] = "broken"})
t.expect(not ok and tostring(err):find("program_source:1", 1, true) ~= nil,
	"compiler errors name the app source line, not the prelude")
ok, err = pcall(ns.ShaderView, {source = good, ["function"] = "missing"})
t.expect(not ok and tostring(err):find("no fragment function named missing", 1, true) ~= nil,
	"a missing function is reported by name")
t.assertThrows(function() ns.ShaderView({source = dir .. "/none.metal", ["function"] = "glow"}) end,
	"a missing source file is an error")

-- A program linked from sources: a library, a snippet, an entry point.
local library = write("library.metal", "static float3 tint(float v) { return float3(v, 0.5, 1.0 - v); }\n")
local entry = write("entry.metal", [==[
fragment float4 linked(ShaderVertex in [[stage_in]], constant ShaderInputs &inputs [[buffer(0)]]) {
	return float4(tint(scale(in.uv.x)), 1.0);
}
]==])
local linked = ns.ShaderView({["function"] = "linked", sources = {
	{path = library}, {code = "static float scale(float x) { return x * 0.5; }"}, {path = entry},
}})
t.expect(linked ~= nil, "a ShaderView links files and snippets into one program, in order")
local broken = write("broken.metal", "static float oops() { return undefined_name; }\n")
ok, err = pcall(ns.ShaderView, {["function"] = "linked", sources = {{path = library}, {path = broken}, {path = entry}}})
t.expect(not ok and tostring(err):find(broken .. ":1", 1, true) ~= nil,
	"errors in a linked program name the file and line they came from")
t.assertThrows(function() ns.ShaderView({["function"] = "linked", sources = {{path = library, code = "x"}}}) end,
	"a source is a path or code, not both")
t.assertThrows(function() ns.ShaderView({source = good, ["function"] = "glow", sources = {{path = good}}}) end,
	"source and sources are exclusive")
local composed = xml.render(string.format([[<ShaderView function="linked">
	<ShaderSource path="%s" />
	<ShaderSource code="static float scale(float x) { return x &gt; 0.5 ? 1.0 : 0.0; }" />
	<ShaderSource path="%s" />
</ShaderView>]], library, entry), {}, ns)
t.expect(composed ~= nil, "<ShaderSource> children link a program from XML, entities decoded")
t.assertThrows(function() xml.render('<ShaderView function="x"><Label text="no" /></ShaderView>', {}, ns) end,
	"a ShaderView takes only ShaderSource children")

local template = write("Stage.etlua", string.format(
	'<ZStack height="120" maxWidth="infinity"><ShaderView id="fx" source="%s" function="glow" /></ZStack>', good))
local stage, refs = xml.renderFile(template, {}, ns)
t.expect(stage ~= nil and refs.fx ~= nil, "<ShaderView> renders from XML with an id")
ns._parityMeasure(stage, {}, {width = 300, height = 120})
t.assertSize(refs.fx, 300, 120, "the shader fills its container")

-- Meshes: draws render into offscreen layers that the view's function
-- finishes from.
local meshes = write("meshes.metal", [==[
struct Flat { float4 position [[position]]; float4 colour; };
// A quad over the left half of the view, coloured from params.
vertex Flat leftQuad(uint id [[vertex_id]], constant ShaderInputs &inputs [[buffer(0)]],
		constant float *params [[buffer(2)]]) {
	float2 corners[6] = {float2(-1, -1), float2(0, -1), float2(-1, 1), float2(0, -1), float2(0, 1), float2(-1, 1)};
	Flat out;
	out.position = float4(corners[id], params[3], 1.0);
	out.colour = float4(params[0], params[1], params[2], 1.0);
	return out;
}
// Points placed from the data buffer: x, y pairs in clip space.
vertex Flat dataQuad(uint id [[vertex_id]], const device float *data [[buffer(1)]]) {
	Flat out;
	out.position = float4(data[id * 2], data[id * 2 + 1], 0.5, 1.0);
	out.colour = float4(0.0, 0.0, 1.0, 1.0);
	return out;
}
fragment float4 flat(Flat in [[stage_in]]) { return in.colour; }
// Layer 1 as is, plus layer 2 added on top.
fragment float4 finish(ShaderVertex in [[stage_in]], texture2d<float> first [[texture(0)]],
		texture2d<float> second [[texture(1)]]) {
	constexpr sampler s(filter::nearest);
	return float4(first.sample(s, in.uv).rgb + second.sample(s, in.uv).rgb, 1.0);
}
]==])
local mesh = ns.ShaderView({source = meshes, ["function"] = "finish", layers = 2, draws = {
	{vertex = "leftQuad", fragment = "flat", count = 6, params = {1, 0, 0, 0.5}},
}})
t.assertEqual(mesh.layers, 2, "a ShaderView keeps offscreen layers for its draws")
t.assertEqual(#mesh.draws, 1, "draws are kept as given")
local function pixel(view, x, y)
	local r, g, b = bridge._shaderPixel(view, 64, 32, x, y)
	return string.format("%d %d %d", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
t.assertEqual(pixel(mesh, 10, 16), "255 0 0", "a draw fills its layer and the finish shows it")
t.assertEqual(pixel(mesh, 50, 16), "0 0 0", "layers clear to transparent black")
mesh.draws = {
	{vertex = "leftQuad", fragment = "flat", count = 6, params = {1, 0, 0, 0.5}},
	{vertex = "leftQuad", fragment = "flat", count = 6, params = {0, 1, 0, 0.5}, blend = "add"},
	{vertex = "leftQuad", fragment = "flat", count = 6, layer = 2, params = {0, 0, 1, 0.5}},
}
t.assertEqual(pixel(mesh, 10, 16), "255 255 255", "added light accumulates, and layers composite in the finish")
mesh.draws = {
	{vertex = "leftQuad", fragment = "flat", count = 6, depth = "write", params = {1, 0, 0, 0.25}},
	{vertex = "leftQuad", fragment = "flat", count = 6, depth = "write", params = {0, 1, 0, 0.75}},
}
t.assertEqual(pixel(mesh, 10, 16), "255 0 0", "depth keeps the nearer surface")
mesh.draws = {
	{vertex = "leftQuad", fragment = "flat", count = 6, params = {1, 0, 0, 0.25}},
	{vertex = "leftQuad", fragment = "flat", count = 6, params = {0, 1, 0, 0.75}},
}
t.assertEqual(pixel(mesh, 10, 16), "0 255 0", "without depth, later draws paint over")
mesh.draws = {{vertex = "dataQuad", fragment = "flat", count = 3, data = {0, -1, 1, -1, 1, 1}}}
t.assertEqual(pixel(mesh, 60, 20), "0 0 255", "vertices can come from Lua data")
t.assertEqual(pixel(mesh, 10, 16), "0 0 0", "a layer left without draws is cleared")
mesh.draws = {}
t.assertEqual(#mesh.draws, 0, "an empty list removes every draw")
t.expect(bridge._shaderFrameTime(mesh, 64, 32) >= 0, "frames with layers can be timed")

local function rejects(draws, message)
	local before = #mesh.draws
	t.assertThrows(function() mesh.draws = draws end, message)
	t.assertEqual(#mesh.draws, before, message .. ", keeping the running draws")
end
mesh.draws = {{vertex = "leftQuad", fragment = "flat", count = 6, params = {1, 1, 1, 0.5}}}
rejects({{vertex = "missing", fragment = "flat", count = 6}}, "an unknown vertex function is rejected")
rejects({{vertex = "leftQuad", fragment = "leftQuad", count = 6}}, "a vertex function is not a fragment")
rejects({{vertex = "leftQuad", fragment = "flat"}}, "a draw needs a count")
rejects({{vertex = "leftQuad", fragment = "flat", count = 6, layer = 3}}, "a draw names one of the view's layers")
rejects({{vertex = "leftQuad", fragment = "flat", count = 6, blend = "multiply"}}, "blend modes are named")
rejects({{vertex = "leftQuad", fragment = "flat", count = 6, primitive = "quad"}}, "primitives are named")
local many = {}
for i = 1, 65 do many[i] = 0 end
rejects({{vertex = "leftQuad", fragment = "flat", count = 6, params = many}}, "params stay small")
mesh.draws = {{vertex = "leftQuad", fragment = "flat", count = 6, layer = 2, params = {1, 1, 1, 0.5}}}
t.assertThrows(function() mesh.layers = 1 end, "layers cannot drop below one a draw uses")
t.assertThrows(function() mesh.layers = 5 end, "a view has at most four layers")
t.assertThrows(function() ns.ShaderView({source = meshes, ["function"] = "finish",
	draws = {{vertex = "leftQuad", fragment = "flat", count = 6}}}) end, "draws need layers")
local fromXml = xml.render(string.format('<ShaderView source="%s" function="finish" layers="2" />', meshes), {}, ns)
t.assertEqual(fromXml.layers, 2, "<ShaderView layers> reaches the view")

-- SwiftUI `.tint` on sliders and toggles sets the native control colour.
local slider = ns.Slider({min = 0, max = 1, value = 0.5, tint = "systemOrange"})
t.expect(slider.trackFillColor ~= nil, "Slider tint fills the track")
local plain = ns.Slider({min = 0, max = 1, value = 0.5})
t.assertEqual(plain.trackFillColor, nil, "an untinted slider keeps the system accent")
local toggle = ns.Toggle({label = "Kick", is_on = true, tint = "systemPink"})
t.expect(toggle.bezelColor ~= nil, "Toggle tint colours the checked control")
local tinted = xml.render('<Toggle label="Snare" value="true" tint="systemTeal" />', {}, ns)
t.expect(tinted.bezelColor ~= nil, "<Toggle tint> reaches the native control")

os.execute("/bin/rm -rf " .. dir)
os.exit(t.summary() and 0 or 1)
