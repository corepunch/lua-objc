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
	local cfg, refs = xml.renderFile(VIEWS .. "Window.xml")

	self.navList = refs.navList
	self.contentList = refs.contentList

	self.navList:replaceRows(Model.navigationItems)
	self.contentList:replaceRows(Model.contentItems)

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
