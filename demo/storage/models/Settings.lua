-- The settings form's one row: a switch, a name and a size threshold. A
-- name must not be empty and a threshold must be one of the picker's
-- options; the constraints refuse anything else.
local Model = require("data.model")

local Settings, Setting = Model:extend("settings", {
	-- The threshold picker's options, in order, and the bytes each keeps.
	thresholds = Model.enum({"Show every folder", "At least 100 MB", "At least 1 GB"}),
	bytes = {0, 100e6, 1e9},
	constraints = {
		deviceName = function(_, name)
			if name == nil or name:match("^%s*$") then return "A device needs a name." end
		end,
		threshold = function(settings, index)
			if settings:model().bytes[index + 1] == nil then return "Choose one of the thresholds." end
		end,
	},
})

function Settings:current() return self:find("device") end

function Setting:minimumBytes() return Settings.bytes[self.threshold + 1] end

return Settings
