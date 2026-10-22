-- The stage: the device alone, on the canvas. Just wide enough for an
-- iPhone-proportioned device at iPad height; the chat receives every
-- other point, unless the chat is hidden and the stage grows.
local Theme = require("apps.studio.models.Theme")
local Model = {}

local STAGE_WIDTH = 440

function Model.presentation()
	return {
		stageWidth = STAGE_WIDTH,
		chatHidden = false,
		tint = Theme.tint,
	}
end

return Model
