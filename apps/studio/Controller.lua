local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.studio.Model")
local Device = require("apps.studio.services.Device")
local Preview = require("apps.studio.services.Preview")
local Versions = require("apps.studio.services.Versions")
local SidebarController = require("apps.studio.controllers.SidebarController")
local PreviewController = require("apps.studio.controllers.PreviewController")
local ChatController = require("apps.studio.controllers.ChatController")
local Projects = require("apps.studio.models.Projects")

local Controller = {}
Controller.__index = Controller

local VIEWS = "apps/studio/views/"
local SEED = {"init.lua", "Model.lua", "Controller.lua", "views/Window.etlua"}
local REPOSITORY = "workspace"

function Controller.new()
	return setmetatable({
		sidebar = SidebarController.new(ns.SidebarMetrics),
		previewPane = PreviewController.new(),
		chat = ChatController.new(),
	}, Controller)
end

function Controller:reloadPreview()
	local controller, err = self.preview:render(self.model.files)
	if controller then
		self.refs.preview.content = controller
		self.refs.previewStatus.text = "Ready"
		return true
	end
	self.refs.previewStatus.text = "Preview failed: " .. tostring(err)
	return nil, err
end

-- Commits the current project; the result replaces the status line.
function Controller:commitProject(message)
	if not self.versions then
		self.refs.previewStatus.text = "Git unavailable: " .. tostring(self.versionsError)
		return nil, self.versionsError
	end
	local id, err = self.versions:record(self.model.files, message)
	if id == nil then
		self.refs.previewStatus.text = "Commit failed: " .. tostring(err)
		return nil, err
	end
	self.refs.previewStatus.text = id and "Committed " .. id:sub(1, 7) or "No changes to commit"
	return id
end

function Controller:createWindow()
	assert(ns.Preview, "Lua Studio requires the iPad runtime. Use make ipad-run.")
	local device, seed = Device.new(ns), {}
	for _, name in ipairs(SEED) do
		local path = "demo/playground/" .. name
		seed[path] = assert(ns._readFile(path))
	end
	self.model = Model.new(device.storage, seed)
	local function readProjectFile(path)
		local value = ns._documentRead(path)
		if value then return value end
		return ns._readFile("apps/studio/Documents/" .. path)
	end
	local projects = Projects.list(readProjectFile, ns.json_parse, ns._jsonEncode, ns._documentWrite)
	self.preview = Preview.new(ns, ns._readFile)
	self.versions, self.versionsError = Versions.open(require("Git"), ns._documentPath(REPOSITORY), function(path, content)
		return ns._documentWrite(REPOSITORY .. "/" .. path, content)
	end)

	local refs
	local config
	config, refs = xml.renderFile(VIEWS .. "Window.etlua", {
		sidebar = self.sidebar:presentation(projects),
		preview = self.previewPane:presentation(),
		chat = self.chat:presentation(),
		actions = {
			toggleChat = function()
				refs.chatPane.hidden = not refs.chatPane.hidden
				refs.chatVisibility.accessibilityLabel = refs.chatPane.hidden and "Show Chat" or "Focus Preview"
			end,
			toggleSidebarWidth = function()
				local compact = refs.sidebar.fixedWidth ~= self.sidebar.metrics.compactWidth
				refs.sidebar.fixedWidth = compact and self.sidebar.metrics.compactWidth or self.sidebar.metrics.expandedWidth
				refs.sidebarWidth.accessibilityLabel = compact and "Widen sidebar" or "Compact sidebar"
			end,
			reloadPreview = function() self:reloadPreview() end,
			commitProject = function() self:commitProject("Update project") end,
		},
	}, ns)
	local controller, err = self.preview:render(self.model.files)
	if controller then
		refs.preview.content = controller
	else
		error("Could not render starter preview: " .. tostring(err))
	end
	self.refs = refs
	-- The first launch commits the starter project, so history has a base.
	if self.versions and #self.versions:log(1) == 0 then self:commitProject("Start project") end
	return ns.Window(config)
end

return Controller
