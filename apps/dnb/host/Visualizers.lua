-- The visualizer extension point: every scene is a plugin in
-- plugins/visualizers/<id>/ with a manifest and a Metal file defining
-- `static float3 <id>Scene(constant ShaderInputs &inputs, float2 uv,
-- const thread Frame &f)`. Scenes are pure presentation: the host analyses
-- the audio once (models/Visuals.lua) and links every scene into one Metal
-- program with its shared library (shaders/Kit.metal) and entry point
-- (shaders/Main.metal), so any two can crossfade. `sections` are where the
-- automatic director shows a scene; the Scene menu can pin any one.
local Plugins = require("Plugins")

local Visualizers = Plugins.extensionPoint({
	name = "visualizer",
	api = 1,
	manifest = {
		title = "string",
		symbol = "string",
		shader = "string",
		sections = "table",
	},
})

-- Index order is the shader's scene numbering and the menu's order.
Visualizers:load("apps.dnb.plugins.visualizers", {"horizon", "landscape", "metaballs", "trails", "tunnel", "crystals"})

-- What views/Visualizer.etlua links: the library, each scene with its
-- function name, and the entry point.
function Visualizers.program()
	local scenes = {}
	for _, plugin in ipairs(Visualizers:list()) do
		assert(plugin.id:match("^[%a][%w]*$"), "scene ids name Metal functions: " .. plugin.id)
		table.insert(scenes, {id = plugin.id, path = plugin.resource(plugin.shader), entry = plugin.id .. "Scene"})
	end
	return {library = "apps/dnb/shaders/Kit.metal", main = "apps/dnb/shaders/Main.metal", scenes = scenes}
end

return Visualizers
