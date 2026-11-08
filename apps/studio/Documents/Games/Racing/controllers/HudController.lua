-- The heads-up display (a game.Hud): the session's status as the HUD
-- template's data.
local HudController = require("game.Hud"):extend({VIEW = "demo/playground/views/sections/Hud.etlua"})

local HINTS = {
	keys = "Up drives · Down brakes · Left and Right steer",
	touch = "Stick steers · A drives · B brakes",
}

local function ordinal(n)
	return n .. (({"st", "nd", "rd"})[n] or "th")
end

function HudController.viewData(status, hud)
	return {
		title = status.title,
		stage = status.stage,
		lap = string.format("Lap %d / %d", status.lap, status.laps),
		place = ordinal(status.place),
		cars = string.format("of %d", status.cars),
		placeLabel = string.format("Place %d of %d", status.place, status.cars),
		bestLap = status.bestLap and string.format("Best lap %.1f s", status.bestLap) or nil,
		countdown = status.countdown,
		hint = hud and hud.touch and HINTS.touch or HINTS.keys,
		message = status.message,
	}
end

return HudController
