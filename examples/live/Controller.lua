local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.live.Model")

local VIEWS = "examples/live/views/"

local ACTIONS = {
	refresh = function(self) self:refresh() end,
}

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		stockList = nil,
		window    = nil,
	}, Controller)
end

function Controller:refresh()
	for _, sym in ipairs(Model.symbols) do
		Model.fetchStock(self.stockList, sym)
	end
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	self.stockList = refs.stockList

	self:refresh()

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
