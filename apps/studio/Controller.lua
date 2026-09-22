local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.studio.Model")
local Device = require("apps.studio.services.Device")
local Preview = require("apps.studio.services.Preview")
local SidebarController = require("apps.studio.controllers.SidebarController")
local PreviewController = require("apps.studio.controllers.PreviewController")
local ChatController = require("apps.studio.controllers.ChatController")

local Controller = {}
Controller.__index = Controller

local VIEWS = "apps/studio/views/"
local SEED = {"init.lua", "Model.lua", "Controller.lua", "views/Window.etlua"}

function Controller.new()
	return setmetatable({
		sidebar = SidebarController.new(ns.SidebarMetrics),
		previewPane = PreviewController.new(),
		chat = ChatController.new(),
	}, Controller)
end

function Controller:createWindow()
	assert(ns.Preview, "Lua Studio requires the iPad runtime. Use make ipad-run.")
	local device, seed = Device.new(ns), {}
	for _, name in ipairs(SEED) do
		local path = "apps/playground/" .. name
		seed[path] = assert(ns._readFile(path))
	end
	self.model = Model.new(device.storage, seed)
	self.preview = Preview.new(ns, ns._readFile)

	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {
		sidebar = self.sidebar:presentation(),
		preview = self.previewPane:presentation(),
		chat = self.chat:presentation(),
	}, ns)
	local controller, err = self.preview:render(self.model.files)
	if controller then
		refs.preview.content = controller
	else
		error("Could not render starter preview: " .. tostring(err))
	end
	self.refs = refs
	return ns.Window(config)
end

return Controller
