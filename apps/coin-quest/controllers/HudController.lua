-- Coin Quest's heads-up display (a game.Hud): the session's status as
-- Hud.etlua's data.
local HudController = require("game.Hud"):extend({VIEW = "apps/coin-quest/views/Hud.etlua"})

-- How to play, for the controls the device has.
local HINTS = {
	keys = "Arrows or WASD run · Space jumps · Q and E turn the camera · Every coin, then the flag",
	touch = "Stick runs · A jumps · X and Y turn the camera · Every coin, then the flag",
}

-- Plain template data for a session status (Model:status()); a touch
-- screen gets the touch controls' hint instead of the keys'.
function HudController.viewData(status, hud)
	local hint = hud and hud.touch and HINTS.touch or HINTS.keys
	local hearts = {}
	for index = 1, status.maxLives do
		table.insert(hearts, {filled = index <= status.lives})
	end
	return {
		level = status.level,
		stage = status.stage,
		coins = string.format("%d / %d", status.coins, status.totalCoins),
		stars = (status.totalStars or 0) > 0 and string.format("%d / %d", status.levelStars, status.totalStars) or nil,
		score = tostring(status.score),
		hearts = hearts,
		lives = string.format("%d of %d lives", status.lives, status.maxLives),
		hint = hint,
		message = status.message and {title = status.message.title, detail = status.message.detail} or nil,
	}
end

return HudController
