-- Coin Quest's stage (a game.Stage): turns the session's scene into
-- Stage.etlua's data, choosing the kit model for each block and prop. The
-- shared stage renders it, poses the nodes every frame and frames the
-- camera, which follows the hero across a level larger than the window.
local Stage = require("game.Stage")
local Blocks = require("apps.coin-quest.catalog.Blocks")
local Props = require("apps.coin-quest.catalog.Props")

local ASSETS = "assets/kenney/platformer-kit/models/"

-- What changes with the landscape: sea and sky.
local BIOMES = {
	grass = {sky = "#9fd6f2", sea = "#2f86c0"},
	snow = {sky = "#cfe0ee", sea = "#3a6f9e"},
}

-- Water surrounds the land; the recovery lawn at y=0 stays visibly dry.
local SEA = {level = -0.45}

-- One sun and one fixed shadow map per level. The broad recovery ground
-- encloses the course; fitting its diagonal leaves room for tree shadows
-- and keeps the map stable as the camera follows the hero.
local SUN = {x = -24, y = 36, z = 20, margin = 6}

local function sunlight(scene)
	local ground = scene.blocks[1]
	local size = Blocks[ground.kind]
	local halfWidth = size.w * ground.scaleX / 2
	local halfDepth = size.d * ground.scaleZ / 2
	return {
		position = string.format("%.3f %.3f %.3f", ground.x + SUN.x, SUN.y, ground.z + SUN.z),
		lookAt = string.format("%.3f 0 %.3f", ground.x, ground.z),
		orthographicScale = math.sqrt(halfWidth * halfWidth + halfDepth * halfDepth) + SUN.margin,
	}
end

local StageController = Stage:extend({VIEW = "apps/coin-quest/views/Stage.etlua"})
local cells = Stage.cells

-- The kit model for a block: its biome's ground, with the grass or snow
-- draping over the edge unless another block stands on it.
function StageController.blockModel(block, biome)
	local size = Blocks[block.kind]
	local variant = (not block.buried and size.overhang) or size.model
	return "block-" .. biome .. variant .. ".glb"
end

function StageController.propModel(kind, biome)
	local prop = Props[kind]
	return ((biome == "snow" and prop.snow) or prop.model) .. ".glb"
end

-- Plain template data for a model scene (Model:scene()).
function StageController.viewData(scene)
	local biome = BIOMES[scene.biome] and scene.biome or "grass"
	local blocks, props = {}, {}
	for _, block in ipairs(scene.blocks) do
		table.insert(blocks, {model = StageController.blockModel(block, biome),
			x = block.x, y = block.y + (block.lift or 0), z = block.z, yaw = block.yaw,
			scaleX = block.scaleX, scaleZ = block.scaleZ, stretch = block.stretch})
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
		camera = StageController:camera(scene.view),
		sun = sunlight(scene),
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

return StageController
