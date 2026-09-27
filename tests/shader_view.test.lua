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

local bad = write("bad.metal", "fragment float4 broken( { }\n")
local ok, err = pcall(ns.ShaderView, {source = bad, ["function"] = "broken"})
t.expect(not ok and tostring(err):find("program_source:1", 1, true) ~= nil,
	"compiler errors name the app source line, not the prelude")
ok, err = pcall(ns.ShaderView, {source = good, ["function"] = "missing"})
t.expect(not ok and tostring(err):find("no fragment function named missing", 1, true) ~= nil,
	"a missing function is reported by name")
t.assertThrows(function() ns.ShaderView({source = dir .. "/none.metal", ["function"] = "glow"}) end,
	"a missing source file is an error")

local template = write("Stage.etlua", string.format(
	'<ZStack height="120" maxWidth="infinity"><ShaderView id="fx" source="%s" function="glow" /></ZStack>', good))
local stage, refs = xml.renderFile(template, {}, ns)
t.expect(stage ~= nil and refs.fx ~= nil, "<ShaderView> renders from XML with an id")
ns._parityMeasure(stage, {}, {width = 300, height = 120})
t.assertSize(refs.fx, 300, 120, "the shader fills its container")

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
