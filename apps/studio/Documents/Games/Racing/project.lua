return {
	name = "Racing",
	bundleId = "org.example.racing",
	appIcon = "flag.checkered",
	projectIcon = "rocket-sketch",
	files = {
		"AGENTS.md", "init.lua", "Controller.lua", "Model.lua",
		"catalog/Kit.lua", "catalog/Tracks.lua",
		"catalog/tracks/oval.lua", "catalog/tracks/hairpin.lua", "catalog/tracks/grandprix.lua",
		"models/Track.lua", "models/Level.lua", "models/World.lua",
		"models/systems/Countdown.lua", "models/systems/Driver.lua", "models/systems/Rivals.lua",
		"models/systems/Bumps.lua", "models/systems/Race.lua",
		"controllers/StageController.lua", "controllers/HudController.lua",
		"views/layouts/Window.etlua", "views/pages/Stage.etlua", "views/sections/Hud.etlua",
		"views/prefabs/Car.etlua",
	},
}
