local Locations = require("apps.diskmap.models.Locations")
local ns = require("AppKit")
local App = require("App")
local xml = require("ui.xml")
local Workflows = require("apps.diskmap.models.Workflows")
local Format = require("apps.diskmap.helpers.Format")
local CollectorController = require("apps.diskmap.controllers.CollectorController")
local Environment = require("apps.diskmap.controllers.Environment")
local Provider = require("apps.diskmap.services.Provider")
local Keep = require("apps.diskmap.flows.Keep")
local Manage = require("apps.diskmap.flows.Manage")
local ScanProgress = require("apps.diskmap.controllers.ScanProgressController")
local NavigationController = require("apps.diskmap.controllers.NavigationController")
local CommandsController = require("apps.diskmap.controllers.CommandsController")
local Model = require("data.model")
local SheetController = require("apps.diskmap.controllers.SheetController")
local PageController = require("data.pagecontroller")
local Location = require("data.location")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local Suggestions = require("apps.diskmap.models.Suggestions")
local Controller = {}; Controller.__index = Controller
local function layout(name) return "apps/diskmap/views/layouts/" .. name .. ".etlua" end
local function render(name, data) return xml.renderFile(layout(name), data or {}, ns) end
function Controller.new(service, launch)
	launch = launch or Provider.launch(App.args(), service)
	local self = setmetatable({launch = launch, query = ""}, Controller)
	local router = {
		open = function(id, params) return self:open(id, params) end,
		show = function(id, params) return self:show(id, params) end,
		search = function(text) return self:search(text) end,
		refresh = function() self:updateRows() end,
		changed = function() self:scanChanged() end,
		basketChanged = function() self:basketChanged() end,
		openHistory = function() self.env.history:open(self.window) end,
		openReview = function(path) self:openReview(path) end,
		keep = function(id) self:keep(id) end,
		destination = function() return self.destination end,
		access = function() self:grantAccess() end,
		openChanges = function()
			if self.env.snapshots and self.env.snapshots.result then self.env.session.changesSheet:open(self.window, self.env.snapshots.result) end
		end,
		shortcuts = function() return self.shortcuts or {} end,
		command = function(name) return self.commandActions[name]() end,
		beforeSheet = function() if self.progress then self.progress:close() end end,
		raise = function() if self.window then self.window:show() end end,
		promptParent = function() return self.window end,
		links = CommandsController.links(),
		onboarded = function(granted)
			self.env.session.fullDiskAccess = granted == true
			self.env.scan:start()
			if self.env.tour:needed(self.env.scan.disk) then self.env.tour:open(self.window) end
		end,
	}
	self.env = Environment.new(service or launch.service, launch, router)
	for _, sheet in pairs(self.env.context.sheets) do SheetController.attach(sheet, self.env.model) end
	self.navigation = NavigationController.new(function(id) self:show(id) end,
		function(location, restoring) self:go(location, restoring) end)
	self.collectorController = CollectorController.new(self.env.context)
	self.progress = ScanProgress.new(self.env.scan)
	self.commands = CommandsController.new(self.env.model, self.env.service, {
		show = function(id, params) self:show(id, params) end,
		destination = function() return self.destination end,
		scanning = function() return self.env.scan.job ~= nil end,
		refresh = function() self.env.scan:start() end,
		cancel = function() self.env.scan:cancel() end,
		settings = function() self:openSettings() end,
		find = function() self:focusSearch() end,
		emptyTrash = function() Manage({app = self.env.context}):manage("user-trash") end,
		navigation = self.navigation,
		review = function() self:openReview() end,
		history = function() self.env.history:open(self.window) end,
		openFolder = function() self:chooseFolder() end,
		quickLook = function() self:quickLook() end,
		canQuickLook = function() local model = self.page and self.page.request; return model ~= nil and model.canQuickLook ~= nil and model:canQuickLook() end,
		openScan = function() self:openScan() end,
		compareScan = function() self:compareScan() end,
		exportScan = function() self:exportScan() end,
		tour = function() self.env.tour:open(self.window) end,
	})
	self.commandActions = self.commands:actions()
	for name, action in pairs(self.commandActions) do self.commandActions[name] = Model.bound(self.env.model, action) end
	return self
end

-- The toolbar's search field: typing opens the Search page over the page it
-- leaves, and clearing it returns there. The query stays with Search, so
-- Back from a result returns to the results; every other page shows the
-- field empty, since no page filters by text.
function Controller:search(text)
	self.query = text or ""
	if self.searchField and self.searchField.stringValue ~= self.query then self.searchField.stringValue = self.query end
	if self.query == "" then
		if self.destination == "search" then self:show(self.returnTo or "overview") end
	elseif self.destination ~= "search" then
		self.returnTo = self.destination
		self:show("search")
	else
		self:updateRows()
	end
end
function Controller:focusSearch()
	if self.window and self.searchField then self.window:focus(self.searchField) end
end
-- Opens a resource where its location sends it: a sidebar page, a sheet of
-- its own, or its category's list with its row selected. An id that names
-- no resource is a page ("updates").
function Controller:open(id, filter)
	local destination = Locations:destination(id) or self.env.manifest.pages[id] and {page = id}
	if not destination then return end
	if destination.page then
		self.env.management:close(); self:show(destination.page)
	elseif destination.sheet == "sdks" then
		self.env.management:close(); self.env.sdks:open(self.window, Locations:find(id))
	else
		self.env.management:open(self.window, destination.category, {filter = filter, select = destination.select})
	end
end

function Controller:state()
	local state = self.env:state()
	state.query = self.query
	return state
end

function Controller:subtitle()
	local text = Scans:summary(self.env.scan.disk, self.env.session.capacity).short or ""
	local marked = self.env.basket:count()
	if marked > 0 then text = text .. " · " .. marked .. " marked for cleanup" end
	return text
end
-- Sidebar sizes come from measured categories and scan-owned inventories.
function Controller:badges()
	local badges = {}
	local summary = Scans:summary(self.env.scan.disk, self.env.session.capacity)
	if summary.available then badges.overview = summary.used end
	-- Clean Up's badge is what it could recover, the number its page leads
	-- with; every other badge is a total stored.
	if self.env.scan.job == nil then
		local eligible = Suggestions:presentation(self.env:sources()).eligibleBytes
		if eligible > 0 then badges.cleanup = Format.size(eligible) end
	end
	local simulators = Categories:row("simulators")
	if simulators and simulators.bytes and simulators.bytes > 0 and not simulators.calculating then badges.simulators = simulators.size end
	-- A workflow's badge is its page's own total, so the sidebar and the page
	-- header name one number.
	local present = self.env:presentWorkflows()
	for _, workflow in ipairs(Workflows:all()) do
		if present[workflow.id] then badges[workflow.id] = workflow:badge() end
	end
	badges.xcode = require("apps.diskmap.models.Inventories"):xcodeBadge()
	badges.projects = require("apps.diskmap.models.Projects"):badge()
	local folder = self.env.requests.folder
	badges.folder = folder and folder:badge()
	return badges
end
function Controller:updateRows()
	if self.env.closed then return end
	if self.window then self.window.subtitle = self:subtitle() end
	-- App facts load once the scan has measured the data folders they need.
	if self.env.model.files and not self.env.model.files.measuring then self.env.inventories:load("applications") end
	-- A page may re-render its template, so its refs are read after updating.
	if self.page then self.page:update(self:state()) end
	self.navigation:setBadges(self:badges())
	self.navigation:setWorkflows(self.env:presentWorkflows())
	self.env.management:draw()
	self.env.sdks:draw()
end
-- A kind of work leads nobody who does not do it (#52): its pages appear
-- once one of its markers exists (Xcode for Developer, Logic Pro for Music
-- Production) or its locations measure enough to matter. Markers are checked
-- once, and a page that appeared stays for the session: a rescan clears
-- sizes, and the sidebar must not lose rows while it runs.

function Controller:basketChanged()
	if self.window then self.window.subtitle = self:subtitle() end
	self.collectorController:update()
	if self.page and self.page.marksChanged then self.page:marksChanged() end
	self.env.review:draw()
end

-- A folder or disk opened with Diskmap (dropped on the window or the Dock
-- icon, chosen with Open Folder…, or `--folder=`) is measured and shown on
-- the Folder Map, whatever page was showing.
function Controller:openFolder(path)
	if type(path) ~= "string" or path == "" then return false end
	self:show("folder", {path = path})
	return true
end

function Controller:chooseFolder()
	local pick = self.env.service.pickFolder
	local path = pick("Open Folder")
	if path then self:openFolder(path) end
end

-- The Overview's access button: the startup disk first when the sandbox
-- hides it (then measure again), otherwise Full Disk Access in Settings.
function Controller:grantAccess()
	if self.env.session.diskAccess == false then
		if self.env.service.requestDiskAccess() then self.env.session.diskAccess = true; self.env.scan:start(); return true end
		return false
	end
	self.env.service.openSettings("privacy")
	return true
end

-- Quick Look (⌘Y) previews the current page's selection.
function Controller:quickLook()
	local model = self.page and self.page.request
	if model and model.quickLook then return model:quickLook() end
	return false
end

-- A running scan shows in its progress window and nowhere else; the pages
-- are drawn when it is over.
function Controller:scanChanged()
	self:updateToolbar()
	local sheetOpen = false
	for _, sheet in pairs(self.env.context.sheets) do if sheet.sheet then sheetOpen = true end end
	if self.env.model.scan.running and self.window and not sheetOpen then
		self.progress:show(self.window)
	else
		self.progress:close()
		self:updateRows()
	end
end
-- After each measurement: refresh capacity and snapshots for hidden space,
-- and record category totals when history is on.


-- Shows page `id` focused on `params`, the way a browser opens a URL
-- (lua/data/location.lua): the page says where it then is, and that is the
-- visit Back returns to. The page showing already is focused again in place.
-- `restoring` is a visit Back or Forward returns to, not a new one.
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
		if self.searchField then self.searchField.stringValue = id == "search" and self.query or "" end
		-- The page that goes is deactivated before the one shown is focused:
		-- the two may be one route, reopened on other params.
		if self.page then self.page:dispose() end
		if request.focus then request:focus(params) end
		local page = PageController.new({page = entry, ns = ns, viewsDir = "apps/diskmap/views/",
			store = self.env.model, request = request, located = function(where) self:located(entry, where) end})
		self.destination, self.page = id, page
		page:mount(self.content, self:state())
		self.navigation:select(id)
		self:updateRows()
	end
	self.restoring = nil
end
-- Shows a location: `/help/shortcuts`, `/folder//Users/me`.
function Controller:go(location, restoring)
	local id, params = Location.parse(location, self.env.manifest.pages)
	self:show(id, params, restoring)
end
-- Where the window is now, as `/page/argument?name=value`.
function Controller:location()
	return self.page and Location.format(self.env.manifest.pages[self.destination], self.page:location())
end
-- Every draw of a page says where it is; a move is a visit.
function Controller:located(entry, where)
	if self.destination ~= entry.id then return end
	self.navigation:visit(Location.format(entry, where), self.restoring)
end

-- Keep or stop keeping location `id`; a save that failed is said in the status.
function Controller:keep(id)
	local _, message = Keep({app = self.env.context}):toggle(id)
	if message then self.env.scan.status = message end
	self:updateRows()
end
-- Exported scans (#37 item 20): metadata only, the format --export-mock
-- writes. Open shows one in its own window; Compare measures it and shows
-- what changed since, like opt-in history without keeping history.
function Controller:exportScan()
	local pick = self.env.service.pickSaveFile
	local path = pick("Export Scan", os.date("Diskmap %Y-%m-%d.diskmapscan"))
	if not path then return end
	self.env.scan.status = "Exporting a metadata-only scan…"; self:updateRows()
	self.env.service.exportMockSnapshot(path, function(result)
		self.env.scan.status = result.failure and result.failure ~= "" and ("Export failed: " .. result.failure)
			or string.format("Exported %d file names and sizes", result.exportedFiles or 0)
		self:updateRows()
	end)
end
local function readScan(path)
	local Mock = require("apps.diskmap.services.Mock")
	local service = Mock.new({fixturePath = path})
	return service
end
function Controller:openScan()
	if self.launch.isolated then
		self.env.service.showError("Cannot open another window", "Leave isolated mode to open a scan in another window.")
		return
	end
	local pick = self.env.service.pickFile
	local path = pick("Open Scan")
	if not path then return end
	local ok, service = pcall(readScan, path)
	if not ok then self.env.service.showError("Could not open the scan", tostring(service)); return end
	Controller.new(service, {secondary = true}):createWindow()
end
function Controller:compareScan(path)
	local pick = self.env.service.pickFile
	path = path or pick("Compare with Scan")
	if not path then return end
	self.env.snapshots = self.env:snapshotComparison(path, false)
	self.env.snapshots:compare()
	self:show("overview")
end
function Controller:openSettings()
	self.env.review:close()
	self.env.settings:open(self.window)
end
function Controller:openReview(path)
	self.env.settings:close()
	self.env.review:open(self.window, path)
end
-- Window.etlua's data. Its toolbar follows the scan as a SwiftUI toolbar
-- follows state: Refresh while idle, Stop in its place while measuring.
function Controller:windowData()
	local data = self.commands:data()
	data.windowTitle = self.env.service.badge and ("Diskmap — " .. self.env.service.badge) or "Diskmap"
	data.subtitle = self:subtitle()
	data.actions = setmetatable({
		search = function(value) self:search(value) end,
		reclaim = function() self:show("cleanup") end,
	}, {__index = self.commandActions})
	data.navigation = not self.launch.isolated
	data.scanning = self.env.scan.job ~= nil
	return data
end
-- The window template is described again only when the scan starts or
-- stops, and only its toolbar is applied.
function Controller:updateToolbar()
	local scanning = self.env.scan.job ~= nil
	if not self.window or self.scanning == scanning then return end
	self.scanning = scanning
	self.window:updateToolbar(xml.toolbarFile(layout("Window"), self:windowData()))
end
function Controller:createWindow()
	self.env:prepare()
	local data = self:windowData()
	self.scanning = data.scanning
	local cfg, windowRefs = render("Window", data)
	self.searchField = windowRefs and windowRefs.search
	self.shortcuts = self.commands:shortcuts(cfg.commands)
	local content, contentRefs = render("Content", {actions = {
		dropToMark = function(paths) return self.collectorController:dropToMark(paths) end,
		dropToOpen = function(paths) return paths[1] ~= nil and self:openFolder(paths[1]) end,
		review = function() self:openReview() end,
		pageDrag = function(targeted) self.collectorController:drag("page", targeted) end,
		collectorDrag = function(targeted) self.collectorController:drag("collector", targeted) end,
	}})
	self.navigation:setWorkflows(self.env:presentWorkflows())
	cfg.content = content
	if not self.launch.isolated then cfg.sidebar = self.navigation:render() end
	self.content, self.collector = contentRefs.content, contentRefs
	self.collectorController.refs = contentRefs
	self:basketChanged()
	self.window = ns.Window(cfg)
	if self.launch.page then self:go(self.launch.page) else self:show("overview") end
	-- Folders dropped on the Dock icon, including the one that launched
	-- Diskmap, open like a folder dropped on the window.
	local onOpen = self.env.service.onOpenFiles
	if not self.launch.isolated and not self.launch.secondary then onOpen(function(paths)
		if paths[1] then self:openFolder(paths[1]) end
		if self.window then self.window:show() end
	end) end
	local folder = self.launch.folder
	if folder then self:openFolder(folder) end

	local exportPath = self.launch.exportPath
	if exportPath then
		self.env.scan.status = "Creating a local metadata-only Mock HDD snapshot…"; self:updateRows()
		self.env.service.exportMockSnapshot(exportPath, function(result)
			if result.failure and result.failure ~= "" then
				self.env.scan.status = "Mock snapshot failed: " .. result.failure
			else
				self.env.scan.status = string.format("Saved %d file names and allocated sizes%s",
					result.exportedFiles or 0, result.partial and " · partial; some locations were inaccessible" or "")
			end
			self:updateRows()
		end)
	elseif self.launch.isolated then
		self.env.scan:start()
	else
		-- First launch without Full Disk Access explains it before the first
		-- scan and starts the scan once access is granted or declined.
		-- The welcome tour follows while the scan runs.

		if self.env.onboarding:needed() then self.env.onboarding:open(self.window)
		else
			self.env.scan:start()
			if self.env.tour:needed(self.env.scan.disk) then self.env.tour:open(self.window) end
		end
	end
	local scope = ns.Scope.current()
	if scope then scope:add(self.env.scan); scope:add({dispose = function() self:dispose() end}) end
	if not self.launch.isolated and not self.launch.secondary then
		self.env.notifications:apply()
		self.env.service.monitor(function() return self.window.visible end, function()
			if self.env.session.monitorEnabled and not self.env.scan.job then self.env.scan:start() end
		end)
	end
	return self.window
end
-- The window is going: its page, sheets and running work go with it.
function Controller:dispose()
	if self.page then self.page:dispose() end
	self.collectorController:dispose()
	if not self.launch.isolated and not self.launch.secondary then self.env.service.onOpenFiles(nil) end
	self.progress:close()
	self.env:dispose()
end
-- A window's code runs with the window's store bound (lua/data/model.lua),
-- and this is where it is bound: the window is entered through a method of
-- its controller or a menu command (bound in `new`). A page's action binds in
-- the page controller, and the service calling back in Provider.bind.
for name, method in pairs(Controller) do
	if type(method) == "function" and name ~= "new" then
		Controller[name] = function(self, ...)
			Model.bind(self.env.model)
			return method(self, ...)
		end
	end
end
return Controller
