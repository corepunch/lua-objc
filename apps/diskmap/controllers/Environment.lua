local Session = require("apps.diskmap.models.Session")
local Keeps = require("apps.diskmap.models.Keeps")
-- The scan-scoped environment. It owns a store, service, scan and route
-- instances independently of a native window. The injected router supplies
-- navigation and presentation; pages ask models for data, never subscribe.
local Model = require("data.model")
local Routes = require("data.routes")
local Manifest = require("data.manifest")
local Store = require("apps.diskmap.Store")
local Contract = require("apps.diskmap.services.Contract")
local Provider = require("apps.diskmap.services.Provider")
local Locations = require("apps.diskmap.models.Locations")
local Scans = require("apps.diskmap.models.Scans")
local Categories = require("apps.diskmap.models.Categories")
local History = require("apps.diskmap.helpers.History")
local Workflows = require("apps.diskmap.models.Workflows")
local Scan = require("apps.diskmap.services.Scan")
local Basket = require("apps.diskmap.flows.Basket")
local Operations = require("apps.diskmap.flows.Operations")
local Rows = require("apps.diskmap.flows.Rows")
local Notifications = require("apps.diskmap.services.Notifications")
local SnapshotComparison = require("apps.diskmap.services.SnapshotComparison")
local InventoryService = require("apps.diskmap.services.Inventories")
local Inventories = require("apps.diskmap.models.Inventories")
local Environment = {}; Environment.__index = Environment

function Environment.new(service, launch, router)
	Contract.check(service)
	local self = setmetatable({launch = launch or {}, router = router, mock = service.mock == true,
		model = Store.new(service.home or os.getenv("HOME") or "/Users"), requests = {}}, Environment)
	self.service = Provider.bind(service, self.model, router.promptParent)
	service = self.service
	if self.mock then for _, row in ipairs(Locations:all()) do row.appIcon = nil end end
	self.model.projectRoots = service.loadFolders("projects") or {}
	Keeps:restore(service.loadKeep())
	self.session = Session:current()
	self.model.includeMedia = service.loadFlag("media") == true
	self.session.monitorEnabled = service.loadSettings() == true
	self.session.historyEnabled = service.loadHistorySetting() == true
	self.manifest = Manifest.load("apps/diskmap/app.xml")
	self.routes = require("apps.diskmap.routes")
	local context = {model = self.model, service = service, manifest = self.manifest, pages = self.manifest.pages, -- Every breakdown page draws its chart in one style, the toolbar's.
		chartStyle = self.launch.chartStyle == "rectangles" and "rectangles" or "rings"}
	for name, value in pairs(router) do context[name] = value end
	self.context = context
	context.request = function(id) return self:page(id) end
	context.scanning = function() return self.scan.job ~= nil end
	context.rescan = function() self.scan:start() end
	context.removed = function(path, bytes, to) self:removed(path, bytes, to) end
	context.trashed = function(path, bytes) self:removed(path, bytes, self.model.home .. "/.Trash") end
	context.remeasure = function(id) self:remeasure(id) end
	context.volumeName = function() return self:state().volumeName end
	context.cleanupSources = function() return self:sources() end
	context.workflowsPresent = function() return self:presentWorkflows() end
	self.basket = Basket({app = context})
	self.basket.results, self.basket.done = {}, {}
	context.basket = self.basket
	self.operations = Operations({app = context})
	context.log = function(...) return self.operations:log(...) end
	self.rowActions = Rows({app = context})
	self.notifications = Notifications.new(self.model, service, {
		mark = function(items) self.rowActions:markAll(items) end,
		review = router.openReview, show = router.raise or function() end,
	})
	self.notifications.isolated = self.launch.isolated
	context.notifications = self.notifications
	self.settings, self.history = self:page("settings"), self:page("history")
	context.snapshotResult = function() return self.snapshots and self.snapshots.result end
	self.tour, self.onboarding = self:page("tour"), self:page("onboarding")
	self.scan = Scan.new(self.model, service, self.model.home, router.changed, function() self:scanFinished() end)
	self.inventories = InventoryService.new(service, router.refresh, function() return self.scan.generation end)
	context.inventories = self.inventories
	local path = service.savedSnapshotPath()
	if not self.mock and path then self.snapshots = self:snapshotComparison(path, true) end
	return self
end

-- A removal changes the measured store. Refresh only the cheap volume query;
-- the disk is walked again only when the user requests another scan.
function Environment:removed(path, bytes, to)
	if self.closed then return end
	Scans:remove(path, bytes, to)
	self.scan.disk = self.service.diskSpace(self.model.home)
	self.router.refresh()
end

-- Owner cleanup measures its one location, with the same lifetime guard as
-- the scan's inventory callbacks.
function Environment:remeasure(id)
	local row = Locations:find(id)
	if self.closed or not row or not row.path then return end
	local scan, generation = self.model.scan, self.scan.generation
	self.service.measure({row.path}, function(sizes)
		if self.closed or self.model.scan ~= scan or self.scan.generation ~= generation then return end
		Scans:resize(id, sizes and sizes[1] or 0)
		self.scan.disk = self.service.diskSpace(self.model.home)
		self.router.refresh()
	end)
end

function Environment:sources()
	return {apps = Inventories:applicationsSummary()}
end

function Environment:prepare()
	self.scan.disk = self.service.diskSpace(self.model.home)
	self.session.capacity = self.service.volumeCapacity(self.model.home)
	if self.session.historyEnabled and not self.launch.isolated then
		self.session.changes = Categories:changes(History.decode(self.service.loadHistory()), 30, 4)
	end
end

function Environment:page(id)
	if not self.requests[id] then
		local entry = self.manifest.pages[id]
		if not entry then error("Unknown Diskmap page: " .. tostring(id), 0) end
		self.requests[id] = Routes.page(Routes.find(self.routes, entry), entry, self.context, "apps.diskmap")
	end
	return self.requests[id]
end

function Environment:state()
	return {disk = self.scan.disk, capacity = self.session.capacity, snapshotCount = self.session.snapshotCount, changes = self.session.snapshotChanges or self.session.changes,
		fullDiskAccess = self.session.fullDiskAccess, diskAccess = self.session.diskAccess,
		mock = self.mock, volumeName = self.mock and self.service.label or "Startup Disk",
		status = (self.service.badge and (self.service.badge .. " · ") or "") .. (not self.model.includeMedia and "Media libraries excluded · " or "") .. self.scan.status}
end

function Environment:presentWorkflows()
	if not self.workflowsPresent then
		local exists = self.service.exists
		self.workflowsPresent = {}
		for _, workflow in ipairs(Workflows:all()) do
			self.workflowsPresent[workflow.id] = workflow:marked(exists)
		end
	end
	for _, workflow in ipairs(Workflows:all()) do
		if not self.workflowsPresent[workflow.id] and workflow:measured() then self.workflowsPresent[workflow.id] = true end
	end
	return self.workflowsPresent
end

function Environment:scanFinished()
	local access = self.service.hasFullDiskAccess
	-- false (known missing) differs from nil (the provider cannot tell).
	self.session.fullDiskAccess = access()
	local disk = self.service.hasDiskAccess
	self.session.diskAccess = disk()
	local capacity = self.service.volumeCapacity
	self.session.capacity = capacity(self.model.home)
	local generation = self.scan.generation
	self.service.snapshotCount(function(count)
		if self.closed or self.scan.generation ~= generation then return end
		self.session.snapshotCount = count; self.router.refresh()
	end)
	-- Clean Up ranks simulators by what the minimal device set would remove,
	-- so the inventory is read whether or not the Simulators page is open.
	self.inventories:refresh()
	if self.session.historyEnabled and not self.launch.isolated then
		local entries = History.append(History.decode(self.service.loadHistory()), Categories:snapshot())
		self.service.saveHistory(History.encode(entries))
		self.session.changes = Categories:changes(entries, 30, 4)
		self.notifications:historyRecorded(entries)
	else
		self.session.changes = nil
	end
	if self.snapshots then self.snapshots:compare() end
end

function Environment:snapshotComparison(path, cache)
	if self.snapshots then self.snapshots:dispose() end
	return SnapshotComparison.new(self.model, self.service, {path = path, cache = cache,
		changed = function(changes, failure)
			self.session.snapshotChanges = changes
			if failure then self.scan.status = "Could not compare with the snapshot: " .. failure end
			self.router.refresh()
		end})
end

function Environment:dispose()
	self.closed = true
	self.context.closed = true
	for _, page in pairs(self.requests) do
		if page.cancel then page:cancel() end
	end
	self.inventories:dispose()
	if self.snapshots then self.snapshots:dispose() end
	self.scan:dispose()
	self.notifications:stop()
end

return Environment
