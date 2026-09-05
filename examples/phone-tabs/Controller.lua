local Model = require("examples.phone-tabs.Model")
local xml   = require("ui.xml")

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:createWindow()
	local ns = require("ns")
	local cfg, refs = xml.renderFile("examples/phone-tabs/views/Window.etlua", {
		recents  = Model.recents,
		favorites = Model.favorites,
		profile  = Model.profile,
	})
	return ns.Window(cfg)
end

return Controller
