-- The game's root controller: the shared game loop (game.Game) with this
-- game's session, tracks, stage and HUD. Up or W drives, Down or S brakes,
-- Left and Right steer, Return continues and R restarts; a game controller
-- (stick steers, A drives, B brakes) or the on-screen one works too.
return require("game.Game"):extend({
	WINDOW = "demo/playground/views/layouts/Window.etlua",
	Model = require("demo.playground.Model"),
	Levels = require("demo.playground.catalog.Tracks"),
	Stage = require("demo.playground.controllers.StageController"),
	Hud = require("demo.playground.controllers.HudController"),
	BINDINGS = {
		buttons = {space = "gas"},
		pad = {a = "gas", b = "brake"},
		tap = "gas",
		turns = {},
		padTurns = {},
	},
})
