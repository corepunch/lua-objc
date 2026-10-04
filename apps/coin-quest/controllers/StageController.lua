-- Owns the 3-D stage: renders Stage.etlua into its host when the scene's
-- structure changes and hands the SceneView fresh poses every frame.
--
-- Rendering copies the model's entities into plain view records, so
-- templates never hold (or mutate) live game state, and frames the camera
-- on the level.
local Template = require("ui.template")

local VIEWS = "apps/coin-quest/views/"
local ASSETS = "apps/coin-quest/assets/models/"

-- The camera looks down on the level from the front at `elevation`
-- degrees. Its field of view is horizontal, so the level's width plus a
-- `margin` of cells either side fits however the window is shaped; a deep
-- level pulls it back further (`depthFit` units per row).
local CAMERA = {elevation = 52, fieldOfView = 52, margin = 2.6, depthFit = 1.9}

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

function StageController.camera(width, depth)
	local cx, cz = (width - 1) / 2, (depth - 1) / 2
	local distance = math.max((width + CAMERA.margin * 2) / 2 / math.tan(math.rad(CAMERA.fieldOfView / 2)),
		depth * CAMERA.depthFit)
	local elevation = math.rad(CAMERA.elevation)
	local function vector(x, y, z) return string.format("%.3f %.3f %.3f", x, y, z) end
	return {
		position = vector(cx, distance * math.sin(elevation), cz + distance * math.cos(elevation)),
		lookAt = vector(cx, 0, cz),
		fieldOfView = CAMERA.fieldOfView,
		fieldOfViewAxis = "horizontal",
	}
end

-- Plain template data for a model scene (Model:scene()).
function StageController.viewData(scene)
	return {
		level = scene.id,
		assets = ASSETS,
		camera = StageController.camera(scene.width, scene.depth),
		tiles = cells(scene.tiles, {"x", "z"}),
		scenery = cells(scene.scenery, {"kind", "x", "z"}),
		start = {x = scene.start.x, z = scene.start.z},
		coins = cells(scene.coins, {"id", "x", "z", "aerial"}),
		keys = cells(scene.keys or {}, {"id", "x", "z"}),
		saws = cells(scene.saws, {"id", "x", "z", "axis"}),
		spikes = cells(scene.spikes, {"id", "x", "z"}),
		platforms = cells(scene.platforms or {}, {"id", "x", "z"}),
		flag = scene.flag.raised and {x = scene.flag.x, z = scene.flag.z} or nil,
	}
end

function StageController:render(scene)
	local data = StageController.viewData(scene)
	data.actions = self.actions
	local _, refs = self.template:update(data)
	self.view = refs.scene
	return self.view
end

function StageController:pose(poses)
	self.view.nodeStates = poses
end

return StageController
