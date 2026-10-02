-- The visualizer extension point: every scene is a plugin in
-- plugins/visualizers/<id>/ with a manifest and a Metal file. A scene either
-- lists `draws`, meshes whose vertex and fragment functions (named after the
-- plugin id) live in its Metal file, or defines only
-- `static float3 <id>Scene(constant ShaderInputs &inputs, float2 uv,
-- const thread Frame &f)` and is drawn full-screen. Scenes are pure
-- presentation: the host analyses the audio once (models/Visuals.lua) and
-- links every scene into one Metal program with its shared library
-- (shaders/Kit.metal) and finishing pass (shaders/Main.metal). Each scene
-- renders into its own layer, so any two can crossfade. `arc` is the range of
-- the track's energy (0…1) in which the automatic director shows a scene; the Scene menu can pin any one.
local Plugins = require("Plugins")

local Visualizers = Plugins.extensionPoint({
	name = "visualizer",
	api = 1,
	manifest = {
		title = "string",
		symbol = "string",
		shader = "string",
		arc = "table",
		draws = "table?",
	},
})

-- Index order is the scene numbering and the menu's order.
Visualizers:load("apps.dnb.plugins.visualizers",
	{"horizon", "landscape", "space", "metaballs", "trails", "tunnel", "crystals"})

-- The draw that shows a full-screen scene: the framework's covering
-- triangle and the fragment wrapper program() generates.
local function fullScreen(id)
	return {vertex = "fullscreenVertex", fragment = id .. "Layer", count = 3}
end

local DRAW_FIELDS = {vertex = "string", fragment = "string", count = "number", instances = "number",
	primitive = "string", blend = "string", depth = "string", cull = "string", params = "table", data = "table"}

-- A scene's draws, checked: its functions carry its id, so scenes linked
-- into one program cannot collide.
local function sceneDraws(plugin)
	if not plugin.draws then return {fullScreen(plugin.id)} end
	assert(#plugin.draws > 0, plugin.id .. " lists no draws")
	for _, draw in ipairs(plugin.draws) do
		for key, value in pairs(draw) do
			assert(DRAW_FIELDS[key] == type(value), string.format("%s draw field %s", plugin.id, tostring(key)))
		end
		for _, stage in ipairs({"vertex", "fragment"}) do
			local name = assert(draw[stage], plugin.id .. " draws need a " .. stage .. " function")
			assert(name == "fullscreenVertex" or name:sub(1, #plugin.id) == plugin.id,
				string.format("%s function %s must start with the scene id", plugin.id, name))
		end
	end
	return plugin.draws
end

-- What views/Visualizer.etlua links: the library, each scene's file, the
-- wrappers of the full-screen scenes, and the finishing pass.
function Visualizers.program()
	local scenes = {}
	for _, plugin in ipairs(Visualizers:list()) do
		assert(plugin.id:match("^[%a][%w]*$"), "scene ids name Metal functions: " .. plugin.id)
		sceneDraws(plugin)
		table.insert(scenes, {id = plugin.id, path = plugin.resource(plugin.shader),
			wrapper = not plugin.draws and plugin.id .. "Layer" or nil, entry = plugin.id .. "Scene"})
	end
	return {library = "apps/dnb/shaders/Kit.metal", main = "apps/dnb/shaders/Main.metal", scenes = scenes}
end

--- The ShaderView draws showing `layers`, a list of 0-based scene indices:
--- layer 1 the current scene, layer 2 the one crossfading in.
function Visualizers.draws(layers)
	local list, result = Visualizers:list(), {}
	for layer, index in ipairs(layers) do
		local plugin = assert(list[index + 1], "no scene " .. tostring(index))
		for _, draw in ipairs(sceneDraws(plugin)) do
			local copy = {layer = layer}
			for key, value in pairs(draw) do copy[key] = value end
			table.insert(result, copy)
		end
	end
	return result
end

return Visualizers
