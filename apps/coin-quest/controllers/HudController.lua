-- Owns the heads-up display over the stage: renders Hud.etlua from the
-- session's status. Unchanged labels keep their views across renders.
local Template = require("ui.template")

local VIEWS = "apps/coin-quest/views/"

local HudController = {}
HudController.__index = HudController

-- How to play, for the controls the device has.
local HINTS = {
	keys = "Arrows or WASD hop · A gap leaps itself · Mushroom pads launch you · Coins, then the flag",
	touch = "Swipe to run · Gaps leap themselves · Tap to stop · Coins, then the flag",
}

-- `options.touch` shows the touch controls' hint instead of the keys'.
function HudController.new(host, ns, options)
	local self = setmetatable({template = Template.new(host, VIEWS .. "Hud.etlua", ns)}, HudController)
	self.hint = (options and options.touch) and HINTS.touch or HINTS.keys
	return self
end

-- Plain template data for a session status (Model:status()).
function HudController.viewData(status, hint)
	local hearts = {}
	for index = 1, status.maxLives do
		table.insert(hearts, {filled = index <= status.lives})
	end
	return {
		level = status.level,
		stage = status.stage,
		coins = string.format("%d / %d", status.coins, status.totalCoins),
		score = tostring(status.score),
		hearts = hearts,
		lives = string.format("%d of %d lives", status.lives, status.maxLives),
		hint = hint or HINTS.keys,
		message = status.message and {title = status.message.title, detail = status.message.detail} or nil,
	}
end

function HudController:render(status)
	local _, refs = self.template:update(HudController.viewData(status, self.hint))
	self.refs = refs
	return refs
end

return HudController
