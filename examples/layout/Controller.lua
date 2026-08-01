local ns    = require("AppKit")
local xml   = require("ui.xml")
local Model = require("examples.layout.Model")

local VIEWS = "examples/layout/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		navList     = nil,
		contentList = nil,
		window      = nil,
	}, Controller)
end

function Controller:createWindow()
	local layout, refs = xml.renderFile(VIEWS .. "LayoutView.xml")

	self.navList = refs.navList
	self.contentList = refs.contentList

	self.navList:replaceRows(Model.navigationItems)
	self.contentList:replaceRows(Model.contentItems)

	self.window = ns.Window {
		title  = Model.title,
		width  = Model.windowWidth,
		height = Model.windowHeight,
		layout,
	}
	return self.window
end

return Controller
