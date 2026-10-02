-- The settings form's data: a switch, a name and a size threshold. A name
-- must not be empty, so its setter refuses it.
local Model = require("data.model")

local Settings = Model.define({id = "settings"})

-- The threshold picker's options, in order (bytes).
Settings.THRESHOLDS = {0, 100e6, 1e9}

function Settings.new()
	return setmetatable({history = false, deviceName = "My Mac", threshold = 0}, Settings)
end

-- What views/Settings.etlua reads.
function Settings:data()
	return {history = self.history, deviceName = self.deviceName, threshold = self.threshold,
		note = "History is " .. tostring(self.history) .. "; name is " .. self.deviceName}
end

function Settings:setHistory(value) self.history = value == true end

function Settings:setDeviceName(value)
	if value == nil or value:match("^%s*$") then return false end
	self.deviceName = value
end

function Settings:setThreshold(index)
	if Settings.THRESHOLDS[index + 1] == nil then return false end
	self.threshold = index
end

function Settings:minimumBytes() return Settings.THRESHOLDS[self.threshold + 1] end

return Settings
