-- The 3-D stage (a game.Stage): turns the session's scene into the Stage
-- template's data. Entities are copied into plain records, so the template
-- never holds live game state.
local Stage = require("game.Stage")
local Kit = require("demo.playground.catalog.Kit")

local StageController = Stage:extend({VIEW = "demo/playground/views/pages/Stage.etlua"})

-- Sky and sea for each biome.
local BIOMES = {
	grass = {sky = "#9fd6f2", sea = "#2f86c0"},
	snow = {sky = "#cfe0ee", sea = "#3a6f9e"},
}

function StageController.viewData(scene)
	local biome = BIOMES[scene.biome] or BIOMES.grass
	local pieces = {}
	for _, piece in ipairs(scene.pieces) do
		table.insert(pieces, {model = piece.model .. ".glb", x = piece.x, y = piece.y, z = piece.z, yaw = piece.yaw, scale = piece.scale})
	end
	local flag = scene.flag
	return {
		level = scene.id,
		assets = Kit.models,
		sky = biome.sky,
		sea = biome.sea,
		camera = StageController:camera(scene.view),
		pieces = pieces,
		start = {x = scene.start.x, y = scene.start.y, z = scene.start.z},
		animation = scene.player.animation,
		coins = Stage.cells(scene.coins, {"id", "x", "y", "z"}),
		springs = Stage.cells(scene.springs, {"id", "x", "y", "z"}),
		spikes = Stage.cells(scene.spikes, {"id", "x", "y", "z"}),
		flag = {x = flag.x, y = flag.y, z = flag.z, raised = flag.raised},
	}
end

return StageController
