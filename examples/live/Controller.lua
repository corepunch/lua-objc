local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.live.Model")

local VIEWS = "examples/live/views/"

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
	local layout, refs = xml.renderFile(VIEWS .. "LiveLayout.xml")

	self.stockList = refs.stockList

	self:refresh()

	self.window = ns.Window {
		title  = Model.title,
		width  = Model.windowWidth,
		height = Model.windowHeight,
		toolbar = {
			{
				id      = "refresh",
				label   = "Refresh",
				icon    = "arrow.clockwise",
				tooltip = "Refresh market data",
				action  = function() self:refresh() end,
			},
		},
		layout,
	}
	return self.window
end

return Controller
