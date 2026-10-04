-- Owns the 3-D stage: renders Stage.etlua into its host when the scene's
-- structure changes and hands the SceneView fresh poses every frame,
-- including the camera's, which follows the hero across a level larger
-- than the window.
--
-- Rendering copies the model's entities into plain view records, so
-- templates never hold (or mutate) live game state.
local Template = require("ui.template")
local Blocks = require("apps.coin-quest.catalog.Blocks")
local Props = require("apps.coin-quest.catalog.Props")

local VIEWS = "apps/coin-quest/views/"
local ASSETS = "apps/coin-quest/assets/models/"

-- The camera itself (where it stands and what it looks at) is the model's
-- (models/systems/Camera.lua); the stage only frames it. A horizontal field
-- of view keeps the same width of world in view however the window is
-- shaped, and the lens looks at a point a little above the hero's feet.
local CAMERA = {fieldOfView = 70, lift = 0.6}

-- What changes with the landscape: sea and sky.
local BIOMES = {
	grass = {sky = "#9fd6f2", sea = "#2f86c0"},
	snow = {sky = "#cfe0ee", sea = "#3a6f9e"},
}

-- The sea's surface, just over the sea floor the lowest blocks stand on.
local SEA = {level = 0.15}

local StageController = {}
StageController.__index = StageController

-- `actions` are the SceneView's `key(view, key, pressed)` and
-- `frame(view, dt)` callbacks.
function StageController.new(host, ns, actions)
	return setmetatable({template = Template.new(host, VIEWS .. "Stage.etlua", ns), actions = actions}, StageController)
end

local function cells(list, fields)
	local records = {}
	for _, item in ipairs(list) do
		local record = {}
		for _, field in ipairs(fields) do record[field] = item[field] end
		table.insert(records, record)
	end
	return records
end

-- The camera's pose for a view `{position, focus}`: where it stands and
-- the point it looks at.
function StageController.cameraPose(view)
	local p, f = view.position, view.focus
	return {id = "camera", x = p.x, y = p.y, z = p.z, lookX = f.x, lookY = f.y + CAMERA.lift, lookZ = f.z}
end

function StageController.camera(view)
	local function vector(x, y, z) return string.format("%.3f %.3f %.3f", x, y, z) end
	local p, f = view.position, view.focus
	return {
		position = vector(p.x, p.y, p.z),
		lookAt = vector(f.x, f.y + CAMERA.lift, f.z),
		fieldOfView = CAMERA.fieldOfView,
		fieldOfViewAxis = "horizontal",
	}
end

-- The kit model for a block: its biome's ground, with the grass or snow
-- draping over the edge unless another block stands on it.
function StageController.blockModel(block, biome)
	local size = Blocks[block.kind]
	local variant = (not block.buried and size.overhang) or size.model
	return "block-" .. biome .. variant .. ".obj"
end

function StageController.propModel(kind, biome)
	local prop = Props[kind]
	return ((biome == "snow" and prop.snow) or prop.model) .. ".obj"
end

-- Plain template data for a model scene (Model:scene()).
function StageController.viewData(scene)
	local biome = BIOMES[scene.biome] and scene.biome or "grass"
	local blocks, props = {}, {}
	for _, block in ipairs(scene.blocks) do
		table.insert(blocks, {model = StageController.blockModel(block, biome),
			x = block.x, y = block.y + (block.lift or 0), z = block.z, yaw = block.yaw, stretch = block.stretch})
	end
	for _, prop in ipairs(scene.props) do
		local model = StageController.propModel(prop.kind, biome)
		-- A piece placed without a turn takes one derived from where it
		-- stands, so repeated props never line up like stamps.
		local turn = prop.yaw or ((prop.x * 73 + prop.z * 151) % 360)
		table.insert(props, {model = model, scale = prop.scale, x = prop.x, y = prop.y, z = prop.z, yaw = turn})
	end
	return {
		level = scene.id,
		assets = ASSETS,
		sky = BIOMES[biome].sky,
		sea = BIOMES[biome].sea,
		seaLevel = SEA.level,
		camera = StageController.camera(scene.view),
		blocks = blocks,
		props = props,
		start = {x = scene.start.x, y = scene.start.y, z = scene.start.z},
		coins = cells(scene.coins, {"id", "x", "y", "z"}),
		stars = cells(scene.stars, {"id", "x", "y", "z"}),
		hearts = cells(scene.hearts, {"id", "x", "y", "z"}),
		keys = cells(scene.keys, {"id", "x", "y", "z"}),
		checkpoints = cells(scene.checkpoints, {"id", "x", "y", "z", "active"}),
		springs = cells(scene.springs, {"id", "x", "y", "z"}),
		gates = cells(scene.gates, {"id", "x", "y", "z"}),
		movers = cells(scene.movers, {"id", "x", "y", "z"}),
		planks = cells(scene.planks, {"id", "x", "y", "z"}),
		saws = cells(scene.saws, {"id", "x", "y", "z", "x2", "z2", "fromX", "fromZ"}),
		spikes = cells(scene.spikes, {"id", "x", "y", "z"}),
		flag = scene.flag.raised and {x = scene.flag.x, y = scene.flag.y, z = scene.flag.z} or nil,
	}
end

function StageController:render(scene)
	local data = StageController.viewData(scene)
	data.actions = self.actions
	local _, refs = self.template:update(data)
	self.view = refs.scene
	return self.view
end

-- The state of the game controller playing, if any (see the SceneView's
-- `gamepad`).
function StageController:gamepad()
	return self.view and self.view.gamepad
end

-- The frame's poses, and the camera's (Model:camera()).
function StageController:pose(poses, view)
	if view then table.insert(poses, StageController.cameraPose(view)) end
	self.view.nodeStates = poses
end

return StageController
