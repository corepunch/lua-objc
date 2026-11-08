-- Coin Quest's root controller: the shared game loop (game.Game) with Coin
-- Quest's session, levels, stage and HUD. Input is game.Input with its
-- default bindings: arrows or WASD run, Space or A jumps, Q/E or X/Y turn
-- the camera, Return continues and R restarts.
return require("game.Game"):extend({
	WINDOW = "apps/coin-quest/views/Window.etlua",
	Model = require("apps.coin-quest.Model"),
	Levels = require("apps.coin-quest.catalog.Levels"),
	Stage = require("apps.coin-quest.controllers.StageController"),
	Hud = require("apps.coin-quest.controllers.HudController"),
})
