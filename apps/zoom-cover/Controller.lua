local ns    = require("AppKit")
local xml   = require("ui.xml")
local Transition = require("ui.transition")
local Model = require("apps.zoom-cover.Model")

local VIEWS = "apps/zoom-cover/views/"

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		showDetail = false,
		ns = Transition.Namespace.new("cover"),
	}, Controller)
end

function Controller:openCover()
	self.showDetail = true
	if self.stack then
		ns.setPresented(self.stack, "showDetail", true)
	end
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua", {
		title = Model.title,
		image = Model.image,
		namespaces = { ns = self.ns },
		actions = {
			openCover = function()
				self:openCover()
			end,
		},
	})
	self.stack = refs and refs.stack or cfg
	return ns.Window(cfg)
end

return Controller
