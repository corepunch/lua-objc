local ns = require("AppKit")
local App = require("App")
local xml = require("ui.xml")
local Overview = require("apps.diskmap.models.Overview")
local Categories = require("apps.diskmap.models.Categories")
local Destinations = require("apps.diskmap.models.Destinations")
local Largest = require("apps.diskmap.models.Largest")
local Recommendations = require("apps.diskmap.models.Recommendations")
local Workflow = require("apps.diskmap.models.Workflow")
local Workflows = require("apps.diskmap.knowledge.Workflows")
local History = require("apps.diskmap.models.History")
local Model = require("apps.diskmap.Model")
local Provider = require("apps.diskmap.services.Provider")
local ScanController = require("apps.diskmap.controllers.ScanController")
local TourController = require("apps.diskmap.controllers.TourController")
local CleanupController = require("apps.diskmap.controllers.CleanupController")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local ManagementController = require("apps.diskmap.controllers.ManagementController")
local SimulatorsController = require("apps.diskmap.controllers.SimulatorsController")
local WorktreesController = require("apps.diskmap.controllers.WorktreesController")
local SdksController = require("apps.diskmap.controllers.SdksController")
local SettingsController = require("apps.diskmap.controllers.SettingsController")
local ActionsController = require("apps.diskmap.controllers.ActionsController")
local ReviewController = require("apps.diskmap.controllers.ReviewController")
local HistoryController = require("apps.diskmap.controllers.HistoryController")
local NavigationController = require("apps.diskmap.controllers.NavigationController")
local OverviewController = require("apps.diskmap.controllers.OverviewController")
local MapController = require("apps.diskmap.controllers.MapController")
local FolderController = require("apps.diskmap.controllers.FolderController")
local FilesController = require("apps.diskmap.controllers.FilesController")
local Files = require("apps.diskmap.models.Files")
local PageController = require("apps.diskmap.controllers.PageController")
local KindsController = require("apps.diskmap.controllers.KindsController")
local ApplicationsController = require("apps.diskmap.controllers.ApplicationsController")
local XcodeController = require("apps.diskmap.controllers.XcodeController")
local ProjectsController = require("apps.diskmap.controllers.ProjectsController")
local DisksController = require("apps.diskmap.controllers.DisksController")
local DuplicatesController = require("apps.diskmap.controllers.DuplicatesController")
local TopicsController = require("apps.diskmap.controllers.TopicsController")
local Guide = require("apps.diskmap.models.Guide")
local Help = require("apps.diskmap.models.Help")
local UpdatesController = require("apps.diskmap.controllers.UpdatesController")
local FilesystemController = require("apps.diskmap.controllers.FilesystemController")
local NotificationsController = require("apps.diskmap.controllers.NotificationsController")
local CommandsController = require("apps.diskmap.controllers.CommandsController")
local SnapshotController = require("apps.diskmap.controllers.SnapshotController")
local WatchlistController = require("apps.diskmap.controllers.WatchlistController")
local WatchedController = require("apps.diskmap.controllers.WatchedController")
local OnboardingController = require("apps.diskmap.controllers.OnboardingController")
local Controller = {}; Controller.__index = Controller
local SCAN_ANIMATION = ns.Animation.snappy()
local function render(name, data) return xml.renderFile("apps/diskmap/views/" .. name .. ".etlua", data or {}, ns) end
-- Services grow optional features; a provider that lacks one simply does not
-- offer it. rawget keeps strict test doubles from reporting a probe as a call.
local function optional(service, name)
	local fn = rawget(service, name)
	return type(fn) == "function" and fn or nil
end
function Controller.new(service)
	service = service or Provider.select(App.args())
	-- A virtual disk brings its own home folder so catalog paths match it.
	local home = rawget(service, "home") or os.getenv("HOME") or "/Users"
	local self = setmetatable({service = service, mock = rawget(service, "mock") == true,
		model = Model.new(home), query = ""}, Controller)
	if self.mock then
		for _, row in ipairs(self.model.resources:leaves()) do row.appIcon = nil end
	end
	local loadFolders = optional(service, "loadFolders")
	self.model.projectRoots = loadFolders and loadFolders("projects") or {}
	-- Only measurement animates: sizes arriving from a scan move the charts
	-- and numbers. Navigation and other refreshes apply immediately.
	self.scan = ScanController.new(self.model, service, home, function()
		ns.withAnimation(SCAN_ANIMATION, function() self:updateRows() end)
	end, function() self:scanFinished() end)
	self.notifications = NotificationsController.new(self.model, service, {
		mark = function(items) self.actions:markAll(items) end,
		review = function() self:openReview() end,
		show = function() if self.window then self.window:show() end end,
	})
	self.settings = SettingsController.new(service, self.model, function() self.scan:start() end, self.notifications)
	self.cleanup = CleanupController.new(self.model, service, function(error)
		if error then self.scan.status = error end
		self:updateRows()
	end)
	self.inspector = InspectorController.new(self.model, service, function() self.scan:start() end)
	self.history = HistoryController.new(service)
	self.review = ReviewController.new(self.model, service, {
		changed = function() self:basketChanged() end,
		rescan = function() self.scan:start() end,
		history = function() self.review:close(); self.history:open(self.window) end,
	})
	self.simulators = SimulatorsController.new(self.model, service, function() self.scan:start() end)
	self.simulators.log = function(...) self.review:log(...) end
	self.simulators.published = function() self:updateRows() end
	self.worktrees = WorktreesController.new(self.model, service, function() self.scan:start() end)
	self.worktrees.log = function(...) self.review:log(...) end
	self.worktrees.published = function() self:updateRows() end
	self.worktrees.showPage = function(id) self:show(id) end
	self.sdks = SdksController.new(self.model, service)
	-- Every list, menu and link opens a resource through this one function.
	local open = function(id) self:open(id) end
	self.management = ManagementController.new(self.model, service, function() self.scan:start() end,
		function(id) self.cleanup:toggleKeep(id) end, open)
	self.navigation = NavigationController.new(function(id, fromHistory) self:show(id, false, fromHistory) end)
	self.watchlist = WatchlistController.new(self.model, service, function() self:updateRows() end)
	self.actions = ActionsController.new(self.model, service, {
		open = open,
		show = function(id) self:show(id) end,
		keep = function(id) self.cleanup:toggleKeep(id) end,
		watch = function(entry) return self.watchlist:menuItem(entry) end,
		refresh = function() self.scan:start() end,
	}, self.review)
	-- A live scan compares with the saved Mock HDD snapshot, the previous
	-- state of this Mac; Mock HDD itself has nothing earlier to compare with.
	if not self.mock then self.snapshots = self:snapshotComparison(Provider.savedSnapshotPath(), true) end
	local files = FilesController.new(self.model, service, self.actions)
	local applications = ApplicationsController.new(self.model, service, self.actions, function(remeasure)
		if remeasure then self.scan:start() else self:updateRows() end
	end)
	applications.showPage = function(id) self:show(id) end
	-- What other pages measured, for every page that states Clean Up's totals,
	-- so they all name the same number.
	local function cleanupSources() return {apps = applications:summary()} end
	self.cleanupSources = cleanupSources
	-- Pages that list catalog resources share one controller; each is a table.
	local resourcePage = function(page)
		return PageController.new(self.model, self.actions, {open = open,
			show = function(id, filter) self:showFiltered(id, filter) end,
			settings = function(section) self.service.openSettings(section) end}, page)
	end
	self.pages = {
		overview = OverviewController.new(self.model, {
			open = open, navigate = function(id) self:show(id) end,
			map = function(id) self.pages.map:setFocus(id); self:show("map") end,
			reclaim = function() self:show("cleanup") end,
			sources = function() return self.cleanupSources and self.cleanupSources() end,
			access = function() self:grantAccess() end,
			menu = function(id) return self.actions:resource(id) end,
			changes = function() if self.snapshots then self.snapshots:open(self.window) end end,
		}),
		map = MapController.new(self.model, self.actions, Provider.mapStyle(App.args())),
		folder = FolderController.new(self.model, service, self.actions, {
			volumeName = function() return self:state().volumeName end,
		}),
		largest = resourcePage(Largest.page),
		files = files,
		kinds = KindsController.new(self.model, function(kind) files:focus(kind); self:show("files", true) end,
			function(id, filter) self:showFiltered(id, filter and Files.filterIndex(filter)) end),
		duplicates = DuplicatesController.new(self.model, service, self.actions),
		cleanup = resourcePage(Recommendations.page(cleanupSources)),
		applications = applications,
		xcode = XcodeController.new(self.model, service, self.actions),
		projects = ProjectsController.new(self.model, service, self.actions, function() self.scan:start() end),
		simulators = self.simulators,
		worktrees = self.worktrees,
		disks = DisksController.new(service, self.actions),
		updates = UpdatesController.new(self.model, service, self.actions, function(id) self:show(id) end, cleanupSources),
		guide = TopicsController.new({id = "guide", topic = "GuideTopic", noun = "guide topic",
			summary = "Where macOS keeps things, why they grow and what is safe to do about them. Sizes are measured on this Mac.",
			present = function(query) return Guide.presentation(self.model, query) end,
			follow = function(topic) return topic.open and function() open(topic.open) end end}),
		filesystem = FilesystemController.new(self.model, service, open),
		watched = WatchedController.new(self.model, service, self.watchlist, self.actions, {
			open = open, closed = function() self:show("overview") end,
		}),
	}
	self.files, self.applications = files, applications
	for _, workflow in ipairs(Workflows.list) do self.pages[workflow.id] = resourcePage(Workflow.page(workflow)) end
	self.commands = CommandsController.new(self.model, service, {
		show = function(id) self:show(id) end,
		destination = function() return self.destination end,
		scanning = function() return self.scan.job ~= nil end,
		refresh = function() self.scan:start() end,
		cancel = function() self.scan:cancel() end,
		settings = function() self:openSettings() end,
		find = function() self:focusSearch() end,
		search = function(id, text) self:search(id, text) end,
		emptyTrash = function() self.inspector:select("user-trash"); self.inspector:manage() end,
		navigation = self.navigation,
		review = function() self:openReview() end,
		history = function() self.history:open(self.window) end,
		openFolder = function() self:chooseFolder() end,
		quickLook = function() self:quickLook() end,
		canQuickLook = function() return self.page ~= nil and self.page.canQuickLook ~= nil and self.page:canQuickLook() end,
		openScan = function() self:openScan() end,
		compareScan = function() self:compareScan() end,
		exportScan = function() self:exportScan() end,
		tour = function() self.tour:open(self.window) end,
	})
	self.commandActions = self.commands:actions()
	-- A help topic's button opens a page or runs a menu command. Its title
	-- and the shortcut list come from the command layer, not the help text.
	local links = CommandsController.links()
	self.pages.help = TopicsController.new({id = "help", topic = "HelpTopic", noun = "help topic",
		summary = "How to find what uses your storage and free up space safely. To search help from anywhere, use the Help menu.",
		present = function(query) return Help.presentation(query, self.shortcuts or {}, links) end,
		follow = function(topic)
			local target = topic.target
			return topic.link and function()
				if self.pages[target] then self:show(target) else self.commandActions[target]() end
			end
		end})
	return self
end
-- Shows a page filtered to `text`, as if typed into the toolbar search:
-- how Help menu search results open their topic.
function Controller:search(id, text)
	self.query = text or ""
	if self.searchField then self.searchField.stringValue = self.query end
	self:show(id, true)
end
function Controller:focusSearch()
	if self.window and self.searchField then self.window:focus(self.searchField) end
end
-- Opens a resource where Destinations sends it: a sidebar page, a sheet of
-- its own, or its category's list with its row selected. An id that names
-- no resource is a page ("updates").
function Controller:open(id, filter)
	local destination = Destinations.resolve(self.model, id) or self.pages[id] and {page = id}
	if not destination then return end
	if destination.page then
		self.management:close(); self:show(destination.page)
	elseif destination.sheet == "sdks" then
		self.management:close(); self.sdks:open(self.window, self.model.resources:find(id))
	else
		self.management:open(self.window, destination.category, {filter = filter, select = destination.select})
	end
end
-- Shows a page narrowed to one of its filters, as Clean Up's pointers to
-- Large Files and Applications do.
function Controller:showFiltered(id, filter)
	if id == "files" then self.files:focus(nil); self.files.filterIndex = filter or 1
	elseif id == "applications" then self.applications:focus(filter) end
	self:show(id, true)
end
-- Everything a page needs to present the current scan, in one value.
function Controller:state()
	return {disk = self.scan.disk, capacity = self.capacity, snapshotCount = self.snapshotCount, changes = self.snapshotChanges or self.changes,
		fullDiskAccess = self.fullDiskAccess, diskAccess = self.diskAccess,
		query = self.query, mock = self.mock, volumeName = self.mock and rawget(self.service, "label") or "Startup Disk",
		status = (rawget(self.service, "badge") and (rawget(self.service, "badge") .. " · ") or "") .. (not self.model.includeMedia and "Media libraries excluded · " or "") .. self.scan.status}
end
function Controller:subtitle()
	local text = Overview.summary(self.model, self.scan.disk, self.capacity).short or ""
	local marked = self.review:count()
	if marked > 0 then text = text .. " · " .. marked .. " marked for cleanup" end
	return text
end
-- Sidebar sizes come from measured categories and from pages that have
-- already loaded their own inventory.
function Controller:badges()
	local badges = {}
	local summary = Overview.summary(self.model, self.scan.disk, self.capacity)
	if summary.available then badges.overview = summary.used end
	-- Clean Up's badge is what it could recover, the number its page leads
	-- with; every other badge is a total stored.
	if self.cleanupSources and self.scan.job == nil then
		local eligible = Recommendations.presentation(self.model, "", self.cleanupSources()).eligibleBytes
		if eligible > 0 then badges.cleanup = Model.size(eligible) end
	end
	local simulators = Categories.row(self.model, "simulators")
	if simulators and simulators.bytes and simulators.bytes > 0 and not simulators.calculating then badges.simulators = simulators.size end
	-- A workflow's badge is its page's own total, so the sidebar and the page
	-- header name one number.
	local present = self:presentWorkflows()
	for _, workflow in ipairs(Workflows.list) do
		if present[workflow.id] then badges[workflow.id] = Workflow.badge(self.model, workflow) end
	end
	for _, id in ipairs({"xcode", "projects", "folder"}) do
		local page = self.pages[id]
		if page.badge then badges[id] = page:badge() end
	end
	return badges
end
function Controller:updateRows()
	if self.window then self.window.subtitle = self:subtitle() end
	-- App facts load once the scan has measured the data folders they need.
	if self.model.files and not self.model.files.measuring then self.pages.applications:load() end
	-- A page may re-render its template, so its refs are read after updating.
	if self.page then self.page:update(self:state()); self.refs = self.page.refs end
	self.navigation:setBadges(self:badges())
	self.navigation:setWatched(self.watchlist:rows())
	self.navigation:setWorkflows(self:presentWorkflows())
	self.management:update()
end
-- A kind of work leads nobody who does not do it (#52): its pages appear
-- once one of its markers exists (Xcode for Developer, Logic Pro for Music
-- Production) or its locations measure enough to matter. Markers are checked
-- once, and a page that appeared stays for the session: a rescan clears
-- sizes, and the sidebar must not lose rows while it runs.
function Controller:presentWorkflows()
	if not self.workflowsPresent then
		local exists = optional(self.service, "exists")
		self.workflowsPresent = {}
		for _, workflow in ipairs(Workflows.list) do
			self.workflowsPresent[workflow.id] = exists ~= nil and Workflow.marked(self.model, workflow, exists) or nil
		end
	end
	for _, workflow in ipairs(Workflows.list) do
		if not self.workflowsPresent[workflow.id] and Workflow.measured(self.model, workflow) then self.workflowsPresent[workflow.id] = true end
	end
	return self.workflowsPresent
end
-- A mark changes the title, the collector and the marked state shown on the
-- current page.
function Controller:basketChanged()
	if self.window then self.window.subtitle = self:subtitle() end
	if self.collector then
		local count = self.review:count()
		ns.withAnimation(ns.Animation.snappy(), function()
			self.collector.collectorText.text = count == 0 and "Drag items here to mark them for cleanup" or self.review:summary()
			self.collector.collectorReview.enabled = count > 0
		end)
	end
	if self.page and self.page.marksChanged then self.page:marksChanged() end
end
-- Files dropped on the collector are marked for cleanup. A catalog location
-- keeps its cleanup rules; any other file or folder is measured first and
-- then validated like everything else in the basket.
function Controller:dropToMark(paths)
	local refused, pending, accepted = {}, {}, 0
	for _, path in ipairs(paths) do
		local resource
		for _, row in ipairs(self.model.resources:leaves()) do
			if row.path == path then resource = row; break end
		end
		local item
		if resource and self.actions:markableResource(resource) then
			local measured = self.model.measurements[resource.id]
			item = {path = path, name = resource.name, bytes = measured and measured.bytes, resourceId = resource.id,
				source = "Dropped", consequence = resource.consequence}
		else
			item = {path = path, name = path:match("([^/]+)$") or path, source = "Dropped"}
			table.insert(pending, item)
		end
		if self.review:isMarked(path) then
			accepted = accepted + 1
		else
			local ok, reason = self.review:toggle(item)
			if ok then accepted = accepted + 1 else table.insert(refused, (item.name or path) .. ": " .. tostring(reason)) end
		end
	end
	if #refused > 0 then self.service.showError("Some items were not marked", table.concat(refused, "\n")) end
	local measure = optional(self.service, "measure")
	if #pending > 0 and measure then
		local list = {}
		for _, item in ipairs(pending) do table.insert(list, item.path) end
		measure(list, function(sizes)
			for index, item in ipairs(pending) do item.bytes = sizes[index] end
			self:basketChanged()
		end)
	end
	return accepted > 0
end
-- A folder or disk opened with Diskmap (dropped on the window or the Dock
-- icon, chosen with Open Folder…, or `--folder=`) is measured and shown on
-- the Folder Map, whatever page was showing.
function Controller:openFolder(path)
	if type(path) ~= "string" or path == "" then return false end
	self.pages.folder:open(path)
	self:show("folder")
	return true
end

function Controller:chooseFolder()
	local pick = optional(self.service, "pickFolder")
	local path = pick and pick("Open Folder")
	if path then self:openFolder(path) end
end

-- The Overview's access button: the startup disk first when the sandbox
-- hides it (then measure again), otherwise Full Disk Access in Settings.
function Controller:grantAccess()
	if self.diskAccess == false then
		if self.service.requestDiskAccess() then self.diskAccess = true; self.scan:start(); return true end
		return false
	end
	self.service.openSettings("privacy")
	return true
end

-- Quick Look (⌘Y) previews the current page's selection.
function Controller:quickLook()
	if self.page and self.page.quickLook then return self.page:quickLook() end
	return false
end

-- After each measurement: refresh capacity and snapshots for hidden space,
-- and record category totals when history is on.
function Controller:scanFinished()
	local access = optional(self.service, "hasFullDiskAccess")
	-- false (known missing) differs from nil (the provider cannot tell).
	if access then self.fullDiskAccess = access() == true else self.fullDiskAccess = nil end
	local disk = optional(self.service, "hasDiskAccess")
	if disk then self.diskAccess = disk() == true else self.diskAccess = nil end
	local capacity = optional(self.service, "volumeCapacity")
	self.capacity = capacity and capacity(self.model.home) or nil
	local snapshots = optional(self.service, "snapshotCount")
	if snapshots then snapshots(function(count) self.snapshotCount = count; self:updateRows() end) end
	-- Clean Up ranks simulators by what the minimal device set would remove,
	-- so the inventory is read whether or not the Simulators page is open.
	if optional(self.service, "simulatorRuntimes") or optional(self.service, "simulatorDevices") then self.simulators:load() end
	if optional(self.service, "worktreeScan") then self.worktrees:load() end
	if self.settings.history then
		local load, save = optional(self.service, "loadHistory"), optional(self.service, "saveHistory")
		if load and save then
			local entries = History.append(History.decode(load()), History.snapshot(self.model))
			save(History.encode(entries))
			self.changes = History.changes(self.model, entries, 30, 4)
			self.notifications:historyRecorded(entries)
		end
	else
		self.changes = nil
	end
	if self.snapshots then self.snapshots:compare() end
	self.watchlist:scanFinished()
end
-- Changes since a snapshot replace history's category totals on the
-- overview: they name locations, not only categories.
function Controller:snapshotComparison(path, cache)
	return SnapshotController.new(self.model, self.service, self.actions, {path = path, cache = cache,
		changed = function(changes, failure)
			self.snapshotChanges = changes
			if failure then self.scan.status = "Could not compare with the snapshot: " .. failure end
			self:updateRows()
		end})
end
-- Mounts a sidebar destination into the content pane. Pages own their
-- templates; the previous page is disposed before the next one mounts.
-- `remount` presents a page again after another page changed its focus;
-- `fromHistory` is set by Back and Forward, which must not record a visit.
-- Pages switch instantly, like any sidebar destination; charts appear drawn.
-- A watched location's sidebar row, "watched:<key>", opens the Watched
-- page focused on that location.
function Controller:show(id, remount, fromHistory)
	local key = id:match("^watched:(.+)$")
	local page = self.pages[key and "watched" or id]
	if not page or not self.content then return end
	if key and not self.watchlist:find(key) then return end
	if self.destination == id and self.page and not remount then return end
	if key then page:focus(key) end
	if self.page then self.page:dispose() end
	self.destination, self.page = id, page
	self.refs = page:mount(self.content, self:state())
	self.navigation:select(id, fromHistory)
	self:updateRows()
end
-- setMapStyle("rings" | "rectangles") switches the Map page's chart.
function Controller:setMapStyle(style)
	self.pages.map:setStyle(style)
end

function Controller:select(id)
	if self.pages.overview.refs then self.pages.overview.selectedId = id end
	self.inspector:select(id)
end
-- Exported scans (#37 item 20): metadata only, the format --export-mock
-- writes. Open shows one in its own window; Compare measures it and shows
-- what changed since, like opt-in history without keeping history.
function Controller:exportScan()
	local pick = optional(self.service, "pickSaveFile")
	local path = pick and pick("Export Scan", os.date("Diskmap %Y-%m-%d.diskmapscan"))
	if not path then return end
	self.scan.status = "Exporting a metadata-only scan…"; self:updateRows()
	self.service.exportMockSnapshot(path, function(result)
		self.scan.status = result.failure and result.failure ~= "" and ("Export failed: " .. result.failure)
			or string.format("Exported %d file names and sizes", result.exportedFiles or 0)
		self:updateRows()
	end)
end
local function measureScan(path)
	local Mock = require("apps.diskmap.services.Mock")
	local service = Mock.new({fixturePath = path})
	return service
end
function Controller:openScan()
	local pick = optional(self.service, "pickFile")
	local path = pick and pick("Open Scan")
	if not path then return end
	local ok, service = pcall(measureScan, path)
	if not ok then self.service.showError("Could not open the scan", tostring(service)); return end
	Controller.new(service):createWindow()
end
function Controller:compareScan(path)
	local pick = optional(self.service, "pickFile")
	path = path or (pick and pick("Compare with Scan"))
	if not path then return end
	self.snapshots = self:snapshotComparison(path, false)
	self.snapshots:compare()
	self:show("overview", true)
end
function Controller:openSettings()
	self.review:close()
	self.settings:open(self.window)
end
function Controller:openReview()
	self.settings:close()
	self.review:open(self.window)
end
function Controller:createWindow()
	self.scan.disk = self.service.diskSpace(self.scan.home)
	if self.service.loadKeep then
		for id, kept in pairs(self.service.loadKeep()) do if (self.model.resources:find(id) or id:match("^simulator:") or id:match("^worktree:")) and kept == true then self.model.kept[id] = true end end
	end
	local capacity = optional(self.service, "volumeCapacity")
	self.capacity = capacity and capacity(self.model.home) or nil
	if self.settings.history then
		local load = optional(self.service, "loadHistory")
		if load then self.changes = History.changes(self.model, History.decode(load()), 30, 4) end
	end
	local actions = setmetatable({
		search = function(value) self.query = value or ""; self:updateRows() end,
		reclaim = function() self:show("cleanup") end,
	}, {__index = self.commandActions})
	local data = self.commands:data()
	data.windowTitle = rawget(self.service, "badge") and ("Diskmap — " .. rawget(self.service, "badge")) or "Diskmap"
	data.subtitle = self:subtitle()
	data.actions = actions
	local cfg, windowRefs = render("Window", data)
	self.searchField = windowRefs and windowRefs.search
	self.shortcuts = self.commands:shortcuts(cfg.commands)
	local content, contentRefs = render("Content", {actions = {
		dropToMark = function(paths) return self:dropToMark(paths) end,
		dropToOpen = function(paths) return paths[1] ~= nil and self:openFolder(paths[1]) end,
		review = function() self:openReview() end,
	}})
	self.navigation:setWatched(self.watchlist:rows())
	self.navigation:setWorkflows(self:presentWorkflows())
	cfg.content, cfg.sidebar = content, self.navigation:render()
	self.content, self.collector = contentRefs.content, contentRefs
	self:basketChanged()
	self.window = ns.Window(cfg)
	self:show(Provider.page(App.args()) or "overview")
	-- Folders dropped on the Dock icon, including the one that launched
	-- Diskmap, open like a folder dropped on the window.
	local onOpen = optional(self.service, "onOpenFiles")
	if onOpen then onOpen(function(paths)
		if paths[1] then self:openFolder(paths[1]) end
		if self.window then self.window:show() end
	end) end
	local folder = Provider.folder(App.args())
	if folder then self:openFolder(folder) end
	self.tour = TourController.new(self.service)
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
		-- First launch without Full Disk Access explains it before the first
		-- scan and starts the scan once access is granted or declined.
		-- The welcome tour follows while the scan runs.
		self.onboarding = OnboardingController.new(self.service, function(granted)
			self.fullDiskAccess = granted == true
			self.scan:start()
			if self.tour:needed(self.scan.disk) then self.tour:open(self.window) end
		end)
		if self.onboarding:needed() then self.onboarding:open(self.window)
		else
			self.scan:start()
			if self.tour:needed(self.scan.disk) then self.tour:open(self.window) end
		end
	end
	local scope = ns.Scope.current()
	if scope then scope:add(self.scan); scope:add({dispose = function()
		if self.page then self.page:dispose() end
		self.pages.folder:cancel()
		if onOpen then onOpen(nil) end
		self.settings:close(); self.management:close(); self.sdks:close()
		self.review:close(); self.history:close(); self.notifications:stop()
	end}) end
	self.notifications:apply()
	self.service.monitor(function() return self.window.visible end, function()
		if self.settings.enabled and not self.scan.job then self.scan:start() end
	end)
	return self.window
end
return Controller
