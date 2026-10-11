local ns = require("AppKit")
local App = require("App")
local xml = require("ui.xml")
local Format = require("apps.diskmap.helpers.Format")
local Environment = require("apps.diskmap.controllers.Environment")
local Provider = require("apps.diskmap.services.Provider")
local Keep = require("apps.diskmap.flows.Keep")
local NavigationController = require("apps.diskmap.controllers.NavigationController")
local CommandsController = require("apps.diskmap.controllers.CommandsController")
local Categories = require("apps.diskmap.models.Categories")
local Model = require("data.model")
local PageController = require("data.pagecontroller")
local Location = require("data.location")
local Controller = {}; Controller.__index = Controller
local function layout(name) return "apps/diskmap/views/layouts/" .. name .. ".etlua" end
local function render(name, data) return xml.renderFile(layout(name), data or {}, ns) end

-- The window's code-behind: it wires the environment, the sidebar, the
-- menus and the toolbar, mounts pages and keeps the browser-like history.
-- Pages draw themselves from models; the controller only shows them.
function Controller.new(service, launch)
	launch = launch or Provider.launch(App.args(), service)
	local self = setmetatable({launch = launch}, Controller)
	local router = {
		show = function(id, params) return self:show(id, params) end,
		refresh = function() self:updateRows() end,
		changed = function() self:measuringChanged() end,
		keep = function(id) self:keep(id) end,
		promptParent = function() return self.window end,
	}
	self.env = Environment.new(service or launch.service, launch, router)
	self.navigation = NavigationController.new(function(id) self:show(id) end,
		function(location, restoring) self:go(location, restoring) end)
	self.commands = CommandsController.new(self.env.service, {
		show = function(id, params) self:show(id, params) end,
		destination = function() return self.destination end,
		measuring = function() return self.env.model.scan.running end,
		refresh = function() self:measure() end,
		cancel = function() self.env.sources:cancel(); self.env.model.scan.running = false; self:measuringChanged() end,
		navigation = self.navigation,
		history = function() self:show("history") end,
		openFolder = function() self:chooseFolder() end,
		quickLook = function() self:quickLook() end,
		canQuickLook = function() local page = self.page and self.page.request; return page ~= nil and page.canQuickLook ~= nil and page:canQuickLook() end,
	})
	self.commandActions = self.commands:actions()
	for name, action in pairs(self.commandActions) do self.commandActions[name] = Model.bound(self.env.model, action) end
	return self
end

function Controller:state() return self.env:state() end

-- The window is titled by its page, as Finder by its folder.
function Controller:windowSubtitle()
	local subtitle, badge = self.pageSubtitle or "", self.env.service.badge
	if not badge then return subtitle end
	return subtitle ~= "" and (badge .. " · " .. subtitle) or badge
end

function Controller:presented(entry, data)
	self.pageTitle, self.pageSubtitle = data.title or entry.title, data.subtitle or ""
	if self.window then self.window.title, self.window.subtitle = self.pageTitle, self:windowSubtitle() end
	self:updateToolbar()
end

-- Sidebar badges: each source's total.
function Controller:badges()
	local badges = {}
	for _, category in ipairs(Categories:all()) do
		local bytes, _, pending = category:totals()
		if bytes > 0 and pending == 0 then badges[category.id] = Format.size(bytes) end
	end
	return badges
end

function Controller:updateRows()
	if self.env.closed then return end
	if self.page then self.page:update(self:state()) end
	self.navigation:setBadges(self:badges())
end

function Controller:measure() self.env.sources:run() end

function Controller:measuringChanged()
	self:updateToolbar()
	self:updateRows()
end

-- A folder opened with Diskmap (dropped on the window or the Dock icon,
-- chosen with Open Folder…, or `--folder=`) shows on the Folder Map.
function Controller:openFolder(path)
	if type(path) ~= "string" or path == "" then return false end
	self:show("folder", {path = path})
	return true
end

function Controller:chooseFolder()
	local path = self.env.service.pickFolder("Open Folder")
	if path then self:openFolder(path) end
end

function Controller:quickLook()
	local page = self.page and self.page.request
	if page and page.quickLook then return page:quickLook() end
	return false
end

-- Shows page `id` focused on `params`, the way a browser opens a URL: the
-- page says where it then is, and that is the visit Back returns to.
function Controller:show(id, params, restoring)
	params = params or {}
	local entry = self.env.manifest.pages[id]
	if not entry then error("Unknown Diskmap page: " .. tostring(id), 0) end
	if not self.content then return end
	local request = self.env:page(entry.id)
	self.restoring = restoring
	if self.destination == id and self.page then
		if request.focus then request:focus(params) end
		self:updateRows()
	else
		if self.page then self.page:dispose() end
		if request.focus then request:focus(params) end
		local page = PageController.new({page = entry, ns = ns, viewsDir = "apps/diskmap/views/",
			store = self.env.model, request = request, located = function(where) self:located(entry, where) end,
			presented = function(data) self:presented(entry, data) end})
		self.destination, self.page = id, page
		page:mount(self.content, self:state())
		self.navigation:select(id)
		self:updateRows()
	end
	self.restoring = nil
end
function Controller:go(location, restoring)
	local id, params = Location.parse(location, self.env.manifest.pages)
	self:show(id, params, restoring)
end
function Controller:location()
	return self.page and Location.format(self.env.manifest.pages[self.destination], self.page:location())
end
function Controller:located(entry, where)
	if self.destination ~= entry.id then return end
	self.navigation:visit(Location.format(entry, where), self.restoring)
end

function Controller:keep(id)
	local _, message = Keep({app = self.env.context}):toggle(id)
	if message then self.env.model.scan.status = message end
	self:updateRows()
end

-- Window.etlua's data. Its toolbar follows the measurement as a SwiftUI
-- toolbar follows state: Measure Again while idle, Stop while measuring.
function Controller:windowData()
	local data = self.commands:data()
	data.windowTitle, data.subtitle = self.pageTitle or "Diskmap", self:windowSubtitle()
	data.actions = setmetatable({}, {__index = self.commandActions})
	data.navigation = not self.launch.isolated
	data.measuring = self.env.model.scan.running
	return data
end

function Controller:updateToolbar()
	local key = tostring(self.env.model.scan.running)
	if not self.window or self.toolbarKey == key then return end
	self.toolbarKey = key
	self.window:updateToolbar(xml.toolbarFile(layout("Window"), self:windowData(), ns))
end

function Controller:createWindow()
	self.env:prepare()
	local data = self:windowData()
	self.toolbarKey = tostring(data.measuring)
	local cfg = render("Window", data)
	self.shortcuts = self.commands:shortcuts(cfg.commands)
	local content, contentRefs = render("Content", {actions = {
		dropToOpen = function(paths) return paths[1] ~= nil and self:openFolder(paths[1]) end,
	}})
	cfg.content = content
	if not self.launch.isolated then cfg.sidebar = self.navigation:render() end
	self.content = contentRefs.content
	self.window = ns.Window(cfg)
	if self.launch.page then self:go(self.launch.page) else self:show("overview") end
	local onOpen = self.env.service.onOpenFiles
	if not self.launch.isolated then onOpen(function(paths)
		if paths[1] then self:openFolder(paths[1]) end
		if self.window then self.window:show() end
	end) end
	if self.launch.folder then self:openFolder(self.launch.folder) end
	self:measure()
	local scope = ns.Scope.current()
	if scope then scope:add({dispose = function() self:dispose() end}) end
	return self.window
end

function Controller:dispose()
	if self.page then self.page:dispose() end
	if not self.launch.isolated then self.env.service.onOpenFiles(nil) end
	self.env:dispose()
end

-- A window's code runs with the window's store bound (lua/data/model.lua).
for name, method in pairs(Controller) do
	if type(method) == "function" and name ~= "new" then
		Controller[name] = function(self, ...)
			Model.bind(self.env.model)
			return method(self, ...)
		end
	end
end
return Controller
