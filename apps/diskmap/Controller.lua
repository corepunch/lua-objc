local ns = require("AppKit")
local App = require("App")
local xml = require("ui.xml")
local Model = require("apps.diskmap.Model")
local Overview = require("apps.diskmap.models.Overview")
local Provider = require("apps.diskmap.services.Provider")
local ScanController = require("apps.diskmap.controllers.ScanController")
local CategoriesController = require("apps.diskmap.controllers.CategoriesController")
local CleanupController = require("apps.diskmap.controllers.CleanupController")
local TipsController = require("apps.diskmap.controllers.TipsController")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local ManagementController = require("apps.diskmap.controllers.ManagementController")
local SimulatorsController = require("apps.diskmap.controllers.SimulatorsController")
local SdksController = require("apps.diskmap.controllers.SdksController")
local SettingsController = require("apps.diskmap.controllers.SettingsController")
local ReclaimController = require("apps.diskmap.controllers.ReclaimController")
local NavigationController = require("apps.diskmap.controllers.NavigationController")
local OverviewController = require("apps.diskmap.controllers.OverviewController")
local LargestController = require("apps.diskmap.controllers.LargestController")
local DeveloperController = require("apps.diskmap.controllers.DeveloperController")
local GuideController = require("apps.diskmap.controllers.GuideController")
local Controller = {}; Controller.__index = Controller
local function render(name, data) return xml.renderFile("apps/diskmap/views/" .. name .. ".etlua", data or {}, ns) end
function Controller.new(service)
	service = service or Provider.select(App.args())
	local home = os.getenv("HOME") or "/Users"
	local self = setmetatable({service = service, mock = rawget(service, "mock") == true,
		model = Model.new(home), query = ""}, Controller)
	if self.mock then
		for _, row in ipairs(self.model.resources:leaves()) do row.appIcon = nil end
	end
	self.scan = ScanController.new(self.model, service, home, function() self:updateRows() end)
	self.settings = SettingsController.new(service, self.model, function() self.scan:start() end)
	self.categories = CategoriesController.new(self.model)
	self.cleanup = CleanupController.new(self.model, service, function(id, filter)
		self.reclaim:close(); self:openManagement(id, filter)
	end, function(error)
		if error then self.scan.status = error end
		self:updateRows()
	end)
	self.tips = TipsController.new(self.model, function(action)
		if action == "settings" then self.service.openSettings("privacy")
		elseif action == "system" then self.reclaim:close(); self:show("guide")
		elseif action == "storage" then self.reclaim:close() end
	end)
	self.reclaim = ReclaimController.new(self.cleanup, self.tips, function() return self.scan.disk end)
	self.inspector = InspectorController.new(self.model, service, function() self.scan:start() end)
	self.simulators = SimulatorsController.new(self.model, service, function() self.scan:start() end)
	self.sdks = SdksController.new(self.model, service)
	self.management = ManagementController.new(self.model, service, function() self.scan:start() end,
		function(id) self.cleanup:toggleKeep(id) end, function() self.simulators:open(self.window) end,
		function(row) self.sdks:open(self.window, row) end)
	self.navigation = NavigationController.new(function(id) self:show(id) end)
	local open = function(id) self:openManagement(id) end
	self.pages = {
		overview = OverviewController.new(self.model, self.categories, {
			open = open, navigate = function(id) self:show(id) end,
			reclaim = function() self:openReclaim() end,
			access = function() self.service.openSettings("privacy") end,
		}),
		largest = LargestController.new(self.model, service, open),
		developer = DeveloperController.new(self.model, {open = open,
			simulators = function() self.simulators:open(self.window) end,
			sdks = function(row) if row then self.sdks:open(self.window, row) end end,
		}),
		guide = GuideController.new(self.model, open),
	}
	return self
end
function Controller:openManagement(id, filter)
	if id == "simulators" then self.simulators:open(self.window) else self.management:open(self.window, id, filter) end
end
-- Everything a page needs to present the current scan, in one value.
function Controller:state()
	return {disk = self.scan.disk, query = self.query, mock = self.mock, volumeName = self.mock and "Mock HDD" or "Startup Disk",
		status = (self.mock and "Mock HDD · " or "") .. (not self.model.includeMedia and "Media libraries excluded · " or "") .. self.scan.status}
end
function Controller:updateRows()
	if self.window then self.window.subtitle = Overview.summary(self.model, self.scan.disk).subtitle or "" end
	-- A page may re-render its template, so its refs are read after updating.
	if self.page then self.page:update(self:state()); self.refs = self.page.refs end
	self.reclaim:update()
	self.management:update()
end
-- Mounts a sidebar destination into the content pane. Pages own their
-- templates; the previous page is disposed before the next one mounts.
function Controller:show(id)
	local page = self.pages[id]
	if not page or not self.content then return end
	if self.destination == id and self.page then return end
	if self.page then self.page:dispose() end
	self.destination, self.page = id, page
	self.refs = page:mount(self.content, self:state())
	self.navigation:select(id)
	self:updateRows()
end
function Controller:select(id)
	if self.pages.overview.refs then self.pages.overview.selectedId = id end
	self.inspector:select(id)
end
function Controller:openReclaim()
	self.settings:close()
	self.reclaim:open(self.window)
end
function Controller:openSettings()
	self.reclaim:close()
	self.settings:open(self.window)
end
function Controller:createWindow()
	self.scan.disk = self.service.diskSpace(self.scan.home)
	if self.service.loadKeep then
		for id, kept in pairs(self.service.loadKeep()) do if self.model.resources:find(id) and kept == true then self.model.kept[id] = true end end
	end
	local cfg = render("Window", {windowTitle = self.mock and "Diskmap — Mock HDD" or "Diskmap",
		subtitle = Overview.summary(self.model, self.scan.disk).subtitle or "",
		actions = {
			search = function(value) self.query = value or ""; self:updateRows() end,
			refresh = function() self.scan:start() end,
			cancel = function() self.scan:cancel() end,
			reclaim = function() self:openReclaim() end,
			settings = function() self:openSettings() end,
		}})
	local content, contentRefs = render("Content")
	cfg.content, cfg.sidebar = content, self.navigation:render()
	self.content = contentRefs.content
	self.window = ns.Window(cfg)
	self:show("overview")
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
		self.reclaim:close(); self.settings:close(); self.management:close(); self.simulators:close(); self.sdks:close()
	end}) end
	self.service.monitor(function() return self.window.visible end, function()
		if self.settings.enabled and not self.scan.job then self.scan:start() end
	end)
	return self.window
end
return Controller
