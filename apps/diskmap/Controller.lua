local ns = require("AppKit")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local System = require("apps.diskmap.services.System")
local ScanController = require("apps.diskmap.controllers.ScanController")
local CategoriesController = require("apps.diskmap.controllers.CategoriesController")
local CleanupController = require("apps.diskmap.controllers.CleanupController")
local TipsController = require("apps.diskmap.controllers.TipsController")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local ManagementController = require("apps.diskmap.controllers.ManagementController")
local SimulatorsController = require("apps.diskmap.controllers.SimulatorsController")
local SettingsController = require("apps.diskmap.controllers.SettingsController")
local Controller = {}; Controller.__index = Controller
local function render(name, data) return xml.renderFile("apps/diskmap/views/" .. name .. ".etlua", data or {}, ns) end
local sections = {
	{name = "Storage", icon = "chart.pie.fill"}, {name = "Cleanup", icon = "trash"},
	{name = "Developer", icon = "hammer"}, {name = "Applications", icon = "app"},
}
function Controller.new(service)
	if service == Controller then service = nil end
	service = service or System
	local home = os.getenv("HOME") or "/Users"
	local self = setmetatable({service = service, model = Model.new(home), section = "Storage", query = ""}, Controller)
	self.scan = ScanController.new(self.model, service, home, function() self:updateRows() end)
	self.settings = SettingsController.new(service)
	self.categories = CategoriesController.new(self.model, function(id)
		if id == "free" or id == "unreconciled" then self:showSection("Settings") else self:openManagement(id) end
	end)
	self.cleanup = CleanupController.new(self.model, service, function(id, filter) self:openManagement(id, filter) end, function(error)
		if error then self.scan.status = error end
		self:updateRows()
	end)
	self.tips = TipsController.new(self.model, function(action)
		if action == "settings" then self.service.openSettings("privacy")
		elseif action == "cleanup" then self:showSection("Cleanup")
		else self:showSection("Storage", action == "system" and "macos" or nil) end
	end)
	self.inspector = InspectorController.new(self.model, service, function() self.scan:start() end)
	self.simulators = SimulatorsController.new(self.model, service, function() self.scan:start() end)
	self.management = ManagementController.new(self.model, service, function() self.scan:start() end,
		function(id) self.cleanup:toggleKeep(id) end, function() self.simulators:open(self.window) end)
	return self
end
function Controller:openManagement(id, filter)
	if id == "simulators" then self.simulators:open(self.window) else self.management:open(self.window, id, filter) end
end
function Controller:updateRows()
	if not self.refs or not self.refs.results then return end
	local rows = self.section == "Cleanup" and self.cleanup:rows(self.query) or self.categories:rows(self.rootId, self.query)
	for _, row in ipairs(rows) do row.children = nil end
	self.refs.results:replaceRows(rows)
	if self.capacity then self.capacity.text = self.categories:capacity(self.scan.disk); self.toolbarTitle:layout() end
	self.refs.coverage.text = self.categories:coverage(self.scan.disk); self.refs.status.text = (not self.model.includeMedia and "Media libraries excluded · " or "") .. self.scan.status
	self.opportunities:update(self.cleanup:presentation())
	self.storageBar:update(self.categories:bar(self.scan.disk))
	self.tipPanel:update(self.tips:presentation(self.scan.disk))
	self.management:update()
	if self.inspector.selectedId then self:select(self.inspector.selectedId, false) end
end
function Controller:select(id, scroll)
	if not self.refs or not self.refs.detailName then return end
	local data = self.inspector:select(id)
	if not data then return end
	self.refs.detailName.text = data.name; self.refs.detailText.text = data.text
	self.refs.location.text = data.location
	self.refs.manage.title = "Manage category…"; self.refs.manage.enabled = true
	self.refs.keep.enabled = true; self.refs.keep.title = data.keepTitle
	self.refs.inspector.hidden = false; self.refs.inspector:layout()
	if scroll ~= false then self.refs.detailName:scrollIntoView() end
end
function Controller:showSection(section, rootId)
	if self.section ~= section or self.rootId ~= rootId then self.inspector.selectedId = nil end
	self.section = section
	self.settingsNavigation:selectRow(section == "Settings" and 0 or nil)
	self.navigation:selectRow(({Storage = 0, Cleanup = 1, Developer = 2, Applications = 3})[section])
	self.rootId = rootId or (section == "Developer" and "developer" or section == "Applications" and "applications" or nil)
	if self.page then self.page:dispose() end
	self.refs = {}
	if section == "Settings" then
		self.page = Template.new(self.content, "apps/diskmap/views/Settings.etlua", ns)
		self.page:update(self.settings:presentation(function()
			if self.settings:toggle() then self:showSection("Settings") else self.service.showError("Could not save Settings", "Try again.") end
		end, function() self.service.openSettings() end, self.model.includeMedia, function()
			if self.model.includeMedia or self.service.confirmAction("Include media libraries", "Measuring Photos, Music and Movies requires enumerating their files. macOS may ask for access. Diskmap reads metadata only. Enable for this session?") then
				self.model.includeMedia = not self.model.includeMedia
				self.scan:start(); self:showSection("Settings")
			end
		end))
		return
	end
	local root = self.rootId and self.model.resources:find(self.rootId)
	self.page = Template.new(self.content, "apps/diskmap/views/Dashboard.etlua", ns)
	local _, refs = self.page:update({title = root and root.name or section == "Cleanup" and "Cleanup" or "Storage categories",
		subtitle = root and root.subtitle or "Understand what is stored, why it exists, and how to manage it.", icon = root and root.icon or "chart.pie.fill", color = root and root.color or "systemBlue",
		coverage = self.categories:coverage(self.scan.disk), status = self.scan.status, actions = {
			measure = function() self.scan:start() end,
			manage = function() self:openManagement(self.inspector.selectedId) end,
			access = function() self.service.openSettings("privacy") end,
			keep = function() self.cleanup:toggleKeep(self.inspector.selectedId) end,
		}})
	self.refs = refs
	ns.Scope.withScope(self.page.scope, function()
		self.opportunities = Template.new(refs.opportunities, "apps/diskmap/views/Opportunities.etlua", ns)
		self.storageBar = Template.new(refs.storageBar, "apps/diskmap/views/StorageBar.etlua", ns)
		self.tipPanel = Template.new(refs.tips, "apps/diskmap/views/Tips.etlua", ns)
		refs.results:onRowSelect(function(_, _, row) if row then self:select(row.id) end end)
		refs.results:onRowActivate(function(_, _, row) if row then self:openManagement(row.id) end end)
	end)
	self:updateRows()
end
function Controller:createWindow()
	self.scan.disk = self.service.diskSpace(self.scan.home)
	if self.service.loadKeep then
		for id, kept in pairs(self.service.loadKeep()) do if self.model.resources:find(id) and kept == true then self.model.kept[id] = true end end
	end
	local cfg, windowRefs = render("Window", {capacity = self.categories:capacity(self.scan.disk),
		actions = {search = function(value) self.query = value; self:updateRows() end}})
	local sidebar, sidebarRefs = render("Sidebar")
	local content, contentRefs = render("ContentPane")
	cfg.sidebar = sidebar; cfg.content = content; self.content = contentRefs.content
	for _, item in ipairs(cfg.toolbar) do
		if item.id == "refresh" then item.action = function() self.scan:start() end end
		if item.id == "cancel" then item.action = function() self.scan:cancel() end end
	end
	self.settingsNavigation = sidebarRefs.settings; self.navigation = sidebarRefs.navigation
	self.settingsNavigation:replaceRows({{name = "Settings", icon = "gearshape"}})
	self.settingsNavigation:onRowSelect(function(_, _, row) if row and self.section ~= "Settings" then self:showSection("Settings") end end)
	self.navigation:replaceRows(sections)
	self.navigation:onRowSelect(function(_, _, row) if row and row.name ~= self.section then self:showSection(row.name) end end)
	self.window = ns.Window(cfg); self.toolbarTitle = windowRefs.toolbarTitle; self.capacity = windowRefs.capacity
	self:showSection("Storage")
	self.scan:start()
	local scope = ns.Scope.current()
	if scope then scope:add(self.scan); scope:add({dispose = function() if self.page then self.page:dispose() end; self.management:close(); self.simulators:close() end}) end
	self.service.monitor(function() return self.window.visible end, function()
		if self.settings.enabled and not self.scan.job then self.scan:start() end
	end)
	return self.window
end
return Controller
