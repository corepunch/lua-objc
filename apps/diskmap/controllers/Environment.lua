local Model = require("data.model")
local Routes = require("data.routes")
local Manifest = require("data.manifest")
local Store = require("apps.diskmap.Store")
local Contract = require("apps.diskmap.services.Contract")
local Provider = require("apps.diskmap.services.Provider")
local Keeps = require("apps.diskmap.models.Keeps")
local Items = require("apps.diskmap.models.Items")
local Sources = require("apps.diskmap.services.Sources")
local Operations = require("apps.diskmap.flows.Operations")
local Environment = {}; Environment.__index = Environment

-- One window's environment: its store, bound service, sources and page
-- instances, independent of a native window. The injected router supplies
-- navigation and presentation; pages ask models for data, never subscribe.
function Environment.new(service, launch, router)
	Contract.check(service)
	local self = setmetatable({launch = launch or {}, router = router, mock = service.mock == true,
		model = Store.new(service.home or os.getenv("HOME") or "/Users"), requests = {}}, Environment)
	self.service = Provider.bind(service, self.model, router.promptParent)
	service = self.service
	self.model.folders = service.loadFolders("projects") or {}
	Keeps:restore(service.loadKeep())
	self.manifest = Manifest.load("apps/diskmap/app.xml")
	self.routes = require("apps.diskmap.routes")
	local context = {model = self.model, service = service, manifest = self.manifest, pages = self.manifest.pages}
	for name, value in pairs(router) do context[name] = value end
	self.context = context
	context.request = function(id) return self:page(id) end
	context.measuring = function() return self.model.scan.running end
	context.measure = function(categories) self.sources:run(categories) end
	context.removed = function(path, bytes) self:removed(path, bytes) end
	context.resized = function(path, bytes) self:resized(path, bytes) end
	context.volumeName = function() return self.mock and self.service.label or "Startup Disk" end
	context.sourceNote = function(id) return self.sources.notes and self.sources.notes[id] end
	self.operations = Operations({app = context})
	context.log = function(...) return self.operations:log(...) end
	self.sources = Sources.new(service, self.model.home, {refresh = router.refresh, changed = router.changed})
	return self
end

-- A removal changes the model; only the cheap free-space query runs again.
function Environment:removed(path, bytes)
	if self.closed then return end
	Items:removed(path, bytes)
	local folder = self.requests.folder
	if folder then folder:changed(path) end
	self.model.disk = self.service.diskSpace(self.model.home)
end

function Environment:resized(path, bytes)
	if self.closed then return end
	Items:resized(path, bytes)
	self.model.disk = self.service.diskSpace(self.model.home)
end

function Environment:prepare()
	self.model.disk = self.service.diskSpace(self.model.home)
	self.model.capacity = self.service.volumeCapacity(self.model.home)
	self.fullDiskAccess = self.service.hasFullDiskAccess()
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
	return {disk = self.model.disk, capacity = self.model.capacity, measuring = self.model.scan.running,
		fullDiskAccess = self.fullDiskAccess, mock = self.mock, volumeName = self.context.volumeName(),
		status = (self.service.badge and (self.service.badge .. " · ") or "") .. (self.model.scan.status or "")}
end

function Environment:dispose()
	self.closed = true
	self.context.closed = true
	for _, page in pairs(self.requests) do
		if page.cancel then page:cancel() end
	end
	self.sources:dispose()
end

return Environment
