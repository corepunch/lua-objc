-- The 3-D stage (a game.Stage): turns the session's scene into the Stage
-- template's data. Entities are copied into plain records, so the template
-- never holds live game state.
local Stage = require("game.Stage")
local Kit = require("demo.playground.catalog.Kit")

local StageController = Stage:extend({VIEW = "demo/playground/views/pages/Stage.etlua"})

-- The kit's own grass and sky.
local LOOK = {sky = "#a8d8f0", ground = "#4d8f6e"}

local function car(entity)
	return {id = entity.id, model = entity.model .. ".glb", x = entity.x, z = entity.z, yaw = entity.yaw}
end

function StageController.viewData(scene)
	local pieces = {}
	for _, piece in ipairs(scene.pieces) do
		table.insert(pieces, {model = piece.model .. ".glb", x = piece.x, y = piece.y, z = piece.z, yaw = piece.yaw, scale = piece.scale})
	end
	local cars = {car(scene.player)}
	for _, rival in ipairs(scene.rivals) do table.insert(cars, car(rival)) end
	return {
		level = scene.id,
		assets = Kit.models,
		sky = LOOK.sky,
		ground = LOOK.ground,
		camera = StageController:camera(scene.view),
		pieces = pieces,
		cars = cars,
		carScale = Kit.carScale,
	}
end

return StageController
