local Model = require("demo.phone-tabs.Model")
local Tabs  = require("demo.phone-tabs.views.Tabs")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local ns = require("ns")
	return ns.Window {
		title = "Phone Tabs",
		content = Tabs(Model),
	}
end

return Controller
