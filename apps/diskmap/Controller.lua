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
local ActionsController = require("apps.diskmap.controllers.ActionsController")
local NavigationController = require("apps.diskmap.controllers.NavigationController")
local OverviewController = require("apps.diskmap.controllers.OverviewController")
local LargestController = require("apps.diskmap.controllers.LargestController")
local FilesController = require("apps.diskmap.controllers.FilesController")
local KindsController = require("apps.diskmap.controllers.KindsController")
local CleanupPageController = require("apps.diskmap.controllers.CleanupPageController")
local ApplicationsController = require("apps.diskmap.controllers.ApplicationsController")
local DeveloperController = require("apps.diskmap.controllers.DeveloperController")
local DisksController = require("apps.diskmap.controllers.DisksController")
local GuideController = require("apps.diskmap.controllers.GuideController")
local UpdatesController = require("apps.diskmap.controllers.UpdatesController")
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
	self.cleanup = CleanupController.new(self.model, service, function(error)
		if error then self.scan.status = error end
		self:updateRows()
	end)
	self.tips = TipsController.new(self.model, function(action)
		if action == "settings" then self.service.openSettings("privacy")
		elseif action == "system" then self:show("guide")
		elseif action == "storage" then self:show("overview") end
	end)
	self.inspector = InspectorController.new(self.model, service, function() self.scan:start() end)
	self.simulators = SimulatorsController.new(self.model, service, function() self.scan:start() end)
	self.sdks = SdksController.new(self.model, service)
	self.management = ManagementController.new(self.model, service, function() self.scan:start() end,
		function(id) self.cleanup:toggleKeep(id) end, function() self:show("simulators") end,
		function(row) self.sdks:open(self.window, row) end)
	self.navigation = NavigationController.new(function(id) self:show(id) end)
	local open = function(id) self:openManagement(id) end
	self.actions = ActionsController.new(self.model, service, {
		open = open,
		show = function(id) self:show(id) end,
		keep = function(id) self.cleanup:toggleKeep(id) end,
		refresh = function() self.scan:start() end,
	})
	local files = FilesController.new(self.model, service, self.actions)
	local applications = ApplicationsController.new(self.model, service, self.actions, function(remeasure)
		if remeasure then self.scan:start() else self:updateRows() end
	end)
	self.pages = {
		overview = OverviewController.new(self.model, self.categories, {
			open = open, navigate = function(id) self:show(id) end,
			reclaim = function() self:show("cleanup") end,
			access = function() self.service.openSettings("privacy") end,
			menu = function(id) return self.actions:resource(id) end,
		}),
		largest = LargestController.new(self.model, self.actions, open),
		files = files,
		kinds = KindsController.new(self.model, function(kind) files:focus(kind); self:show("files", true) end),
		cleanup = CleanupPageController.new(self.model, self.actions, self.tips, {
			open = open,
			show = function(id, filter)
				if id == "files" then files:focus(nil); files.filterIndex = filter or 1
				elseif id == "applications" then applications:focus(filter) end
				self:show(id, true)
			end,
			apps = function() return applications:summary() end,
		}),
		applications = applications,
		developer = DeveloperController.new(self.model, self.actions, {open = open,
			simulators = function() self:show("simulators") end,
			sdks = function(row) if row then self.sdks:open(self.window, row) end end,
		}),
		simulators = self.simulators,
		disks = DisksController.new(service, self.actions),
		updates = UpdatesController.new(self.model, service),
		guide = GuideController.new(self.model, open),
	}
	return self
end
-- Destinations that open a sidebar page rather than a category sheet: the
-- simulator device resource is managed on its page, and "updates" names the
-- Updates & Snapshots page. Developer stays a sheet so its page can list it.
local PAGE_ROUTES = {simulators = true, updates = true}
function Controller:openManagement(id, filter)
	if PAGE_ROUTES[id] then self.management:close(); self:show(id) else self.management:open(self.window, id, filter) end
end
-- Everything a page needs to present the current scan, in one value.
function Controller:state()
	return {disk = self.scan.disk, query = self.query, mock = self.mock, volumeName = self.mock and "Mock HDD" or "Startup Disk",
		status = (self.mock and "Mock HDD · " or "") .. (not self.model.includeMedia and "Media libraries excluded · " or "") .. self.scan.status}
end
function Controller:updateRows()
	if self.window then self.window.subtitle = Overview.summary(self.model, self.scan.disk).subtitle or "" end
	-- App facts load once the scan has measured the data folders they need.
	if self.model.files then self.pages.applications:load() end
	-- A page may re-render its template, so its refs are read after updating.
	if self.page then self.page:update(self:state()); self.refs = self.page.refs end
	self.management:update()
end
-- Mounts a sidebar destination into the content pane. Pages own their
-- templates; the previous page is disposed before the next one mounts.
-- `remount` presents a page again after another page changed its focus.
function Controller:show(id, remount)
	local page = self.pages[id]
	if not page or not self.content then return end
	if self.destination == id and self.page and not remount then return end
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
function Controller:openSettings()
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
			reclaim = function() self:show("cleanup") end,
			settings = function() self:openSettings() end,
		}})
	local content, contentRefs = render("Content")
	cfg.content, cfg.sidebar = content, self.navigation:render()
	self.content = contentRefs.content
	self.window = ns.Window(cfg)
	self:show(Provider.page(App.args()) or "overview")
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
		self.settings:close(); self.management:close(); self.sdks:close()
	end}) end
	self.service.monitor(function() return self.window.visible end, function()
		if self.settings.enabled and not self.scan.job then self.scan:start() end
	end)
	return self.window
end
return Controller
