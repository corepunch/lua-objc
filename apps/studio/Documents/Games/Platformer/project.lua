return {
	name = "Platformer",
	bundleId = "org.example.platformer",
	appIcon = "gamecontroller.fill",
	projectIcon = "rocket-sketch",
	files = {
		"AGENTS.md", "init.lua", "Controller.lua", "Model.lua",
		"catalog/Kit.lua", "catalog/Levels.lua",
		"catalog/levels/meadow.lua", "catalog/levels/hills.lua", "catalog/levels/peak.lua",
		"models/Ground.lua", "models/Level.lua", "models/World.lua",
		"models/systems/Hero.lua", "models/systems/Springs.lua", "models/systems/Pickups.lua", "models/systems/Hazards.lua",
		"controllers/StageController.lua", "controllers/HudController.lua",
		"views/layouts/Window.etlua", "views/pages/Stage.etlua", "views/sections/Hud.etlua",
		"views/prefabs/Player.etlua", "views/prefabs/Coin.etlua", "views/prefabs/Flag.etlua",
		"views/prefabs/Spring.etlua", "views/prefabs/Spikes.etlua",
	},
}
