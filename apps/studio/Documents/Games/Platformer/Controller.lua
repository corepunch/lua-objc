-- The game's root controller: the shared game loop (game.Game) with this
-- game's session, levels, stage and HUD. Arrows or WASD run, Space jumps,
-- Q and E turn the camera, Return continues and R restarts; a game
-- controller or the on-screen one works too.
return require("game.Game"):extend({
	WINDOW = "demo/playground/views/layouts/Window.etlua",
	Model = require("demo.playground.Model"),
	Levels = require("demo.playground.catalog.Levels"),
	Stage = require("demo.playground.controllers.StageController"),
	Hud = require("demo.playground.controllers.HudController"),
})
