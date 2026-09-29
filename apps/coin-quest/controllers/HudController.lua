-- Owns the heads-up display over the stage: renders Hud.etlua from the
-- session's status. Unchanged labels keep their views across renders.
local Template = require("ui.template")

local VIEWS = "apps/coin-quest/views/"

local HudController = {}
HudController.__index = HudController

function HudController.new(host, ns)
	return setmetatable({template = Template.new(host, VIEWS .. "Hud.etlua", ns)}, HudController)
end

-- Plain template data for a session status (Model:status()).
function HudController.viewData(status)
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
		message = status.message and {title = status.message.title, detail = status.message.detail} or nil,
	}
end

function HudController:render(status)
	local _, refs = self.template:update(HudController.viewData(status))
	self.refs = refs
	return refs
end

return HudController
