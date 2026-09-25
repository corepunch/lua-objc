local ns = require("AppKit")
local App = require("App")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Provider = require("apps.diskmap.services.Provider")
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
local function monitorTitle(enabled)
	return enabled and "Pause background checks" or "Enable background checks"
end
local function mediaTitle(enabled)
	return enabled and "Exclude media libraries" or "Include media libraries for this session…"
end
function Controller.new(service)
	if service == Controller then service = nil end
	service = service or Provider.select(App.args())
	local home = os.getenv("HOME") or "/Users"
	local self = setmetatable({service = service, mock = rawget(service, "mock") == true,
		model = Model.new(home), query = "", reclaimQuery = ""}, Controller)
	if self.mock then
		for _, row in ipairs(self.model.resources:leaves()) do row.appIcon = nil end
	end
	self.scan = ScanController.new(self.model, service, home, function() self:updateRows() end)
	self.settings = SettingsController.new(service)
	self.categories = CategoriesController.new(self.model, function(id)
		if id == "free" or id == "unreconciled" then self:openSettings() else self:openManagement(id) end
	end)
	self.cleanup = CleanupController.new(self.model, service, function(id, filter)
		self:closeReclaim(); self:openManagement(id, filter)
	end, function(error)
		if error then self.scan.status = error end
		self:updateRows()
	end)
	self.tips = TipsController.new(self.model, function(action)
		if action == "settings" then self.service.openSettings("privacy")
		elseif action == "system" then self:closeReclaim(); self:openManagement("macos")
		elseif action == "storage" then self:closeReclaim() end
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
	if not self.refs then return end
	if self.refs.results then
		local rows = self.categories:rows(nil, self.query)
		for _, row in ipairs(rows) do row.children = nil end
		self.refs.results:replaceRows(rows)
	end
	if self.capacity then self.capacity.text = self.categories:capacity(self.scan.disk); self.toolbarTitle:layout() end
	if self.refs.coverage then
		self.refs.coverage.text = self.categories:coverage(self.scan.disk)
		self.refs.status.text = (self.mock and "Mock HDD · " or "") .. (not self.model.includeMedia and "Media libraries excluded · " or "") .. self.scan.status
		self.refs.access.title = self.mock and "Mock HDD active" or (self.model.scan.errors or 0) > 0 and "Review scan access…" or "Scan access…"
		self.refs.access.enabled = not self.mock
	end
	if self.opportunities then self.opportunities:update(self.cleanup:presentation(self.reclaimQuery)) end
	if self.storageBar then self.storageBar:update(self.categories:bar(self.scan.disk)) end
	if self.tipPanel then self.tipPanel:update(self.tips:presentation(self.scan.disk)) end
	self.management:update()
	if self.refs.results and self.inspector.selectedId then self:select(self.inspector.selectedId) end
end
function Controller:select(id)
	if not self.refs or not self.refs.openCategory then return end
	if not self.inspector:select(id) then return end
	self.refs.openCategory.enabled = true
end
function Controller:closeReclaim()
	if self.reclaimSheet then ns.dismiss(self.reclaimSheet); self.reclaimSheet = nil end
	if self.reclaimScope then self.reclaimScope:close(); self.reclaimScope = nil end
	self.reclaimRefs, self.opportunities, self.tipPanel = nil, nil, nil
end
function Controller:openReclaim()
	self:closeSettings(); self:closeReclaim()
	self.reclaimQuery = ""
	self.reclaimScope = ns.Scope.new()
	ns.Scope.withScope(self.reclaimScope, function()
		self.reclaimSheet, self.reclaimRefs = render("Reclaim", {actions = {
			search = function(value) self.reclaimQuery = value or ""; self:updateRows() end,
			done = function() self:closeReclaim() end,
		}})
		self.reclaimRefs.done.keyEquivalent = "\r"
		self.reclaimSheet.defaultButtonCell = self.reclaimRefs.done.cell
		self.opportunities = Template.new(self.reclaimRefs.opportunities, "apps/diskmap/views/Opportunities.etlua", ns)
		self.tipPanel = Template.new(self.reclaimRefs.tips, "apps/diskmap/views/Tips.etlua", ns)
	end)
	self:updateRows()
	ns.presentSheet(self.reclaimSheet, self.window); ns.focus(self.reclaimSheet, self.reclaimRefs.search)
end
function Controller:closeSettings()
	if self.settingsSheet then ns.dismiss(self.settingsSheet); self.settingsSheet = nil end
	if self.settingsScope then self.settingsScope:close(); self.settingsScope = nil end
	self.settingsRefs = nil
end
function Controller:openSettings()
	self:closeReclaim(); self:closeSettings()
	self.settingsScope = ns.Scope.new()
	local data = self.settings:presentation(function()
		if self.settings:toggle() then
			if self.settingsRefs then self.settingsRefs.monitor.title = monitorTitle(self.settings.enabled) end
		else self.service.showError("Could not save Settings", "Try again.") end
	end, function() self.service.openSettings() end, function() self.service.openSettings("privacy") end, self.model.includeMedia, function()
		local message = self.mock and "Include the synthetic Photos, Music and Movies entries in this session? Mock HDD reads only its bundled fixture." or "Measuring Photos, Music and Movies requires enumerating their files. macOS may ask for access. Diskmap reads metadata only. Enable for this session?"
		if self.model.includeMedia or self.service.confirmAction("Include media libraries", message) then
			self.model.includeMedia = not self.model.includeMedia
			if self.settingsRefs then self.settingsRefs.media.title = mediaTitle(self.model.includeMedia) end
			self.scan:start()
		end
	end)
	data.actions.done = function() self:closeSettings() end
	ns.Scope.withScope(self.settingsScope, function()
		self.settingsSheet, self.settingsRefs = render("Settings", data)
		self.settingsRefs.done.keyEquivalent = "\r"
		self.settingsSheet.defaultButtonCell = self.settingsRefs.done.cell
	end)
	ns.presentSheet(self.settingsSheet, self.window)
end
function Controller:mountDashboard()
	if self.page then self.page:dispose() end
	self.refs = {}
	self.storageBar = nil
	self.page = Template.new(self.content, "apps/diskmap/views/Dashboard.etlua", ns)
	local _, refs = self.page:update({
		coverage = self.categories:coverage(self.scan.disk), status = self.scan.status, actions = {
			openCategory = function() if self.inspector.selectedId then self:openManagement(self.inspector.selectedId) end end,
			reclaim = function() self:openReclaim() end,
			access = function() self.service.openSettings("privacy") end,
		}})
	self.refs = refs
	ns.Scope.withScope(self.page.scope, function()
		self.storageBar = Template.new(refs.storageBar, "apps/diskmap/views/StorageBar.etlua", ns)
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
		windowTitle = self.mock and "Diskmap — Mock HDD" or "Diskmap",
		actions = {
			search = function(value) self.query = value; self:updateRows() end,
			refresh = function() self.scan:start() end,
			cancel = function() self.scan:cancel() end,
			settings = function() self:openSettings() end,
		}})
	local content, contentRefs = render("ContentPane")
	cfg.content = content; self.content = contentRefs.content
	self.window = ns.Window(cfg); self.toolbarTitle = windowRefs.toolbarTitle; self.capacity = windowRefs.capacity
	self:mountDashboard()
	local exportPath = Provider.exportPath(App.args())
	if exportPath then
		self.scan.status = "Creating a local metadata-only Mock HDD snapshot…"; self:updateRows()
		self.service.exportMockSnapshot(exportPath, function(result)
			if result.failure and result.failure ~= "" then
				self.scan.status = "Mock snapshot failed: " .. result.failure
			else
				self.scan.status = string.format("Saved %d file names and allocated sizes%s",
					result.exportedFiles or 0, result.partial and " · partial; some locations were inaccessible" or "")
			end
			self:updateRows()
		end)
	else
		self.scan:start()
	end
	local scope = ns.Scope.current()
	if scope then scope:add(self.scan); scope:add({dispose = function()
		if self.page then self.page:dispose() end
		self:closeReclaim(); self:closeSettings(); self.management:close(); self.simulators:close()
	end}) end
	self.service.monitor(function() return self.window.visible end, function()
		if self.settings.enabled and not self.scan.job then self.scan:start() end
	end)
	return self.window
end
return Controller
