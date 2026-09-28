local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("demo.component-gallery.Model")

local VIEWS = "demo/component-gallery/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model.new() }, Controller)
end

function Controller:render()
	self.gallery:update(self.model:snapshot())
end

-- Components are retained: the next day's values move the existing rings,
-- bars and cells inside this animation instead of rebuilding them.
function Controller:advance()
	self.model:advance()
	ns.withAnimation(ns.Animation.snappy(), function() self:render() end)
end

function Controller:createWindow()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {}, ns)
	for _, item in ipairs(config.toolbar or {}) do
		if item.action == "advance" then item.action = function() self:advance() end end
	end
	self.window = ns.Window(config)
	self.gallery = Template.new(refs.host, VIEWS .. "Gallery.etlua", ns)
	self:render()
	return self.window
end

return Controller
