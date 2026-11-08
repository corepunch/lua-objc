-- The heads-up display (a game.Hud): the session's status as the HUD
-- template's data.
local HudController = require("game.Hud"):extend({VIEW = "demo/playground/views/sections/Hud.etlua"})

local HINTS = {
	keys = "Arrows or WASD run · Space jumps · Q and E turn the camera",
	touch = "Stick runs · A jumps · X and Y turn the camera",
}

function HudController.viewData(status, hud)
	local hearts = {}
	for index = 1, status.maxLives do table.insert(hearts, {filled = index <= status.lives}) end
	return {
		title = status.title,
		stage = status.stage,
		coins = string.format("%d / %d", status.coins, status.totalCoins),
		hearts = hearts,
		lives = string.format("%d of %d lives", status.lives, status.maxLives),
		hint = hud and hud.touch and HINTS.touch or HINTS.keys,
		message = status.message,
	}
end

return HudController
