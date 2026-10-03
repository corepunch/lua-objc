-- Shared discovery has a scan lifetime, independent of whether a page is
-- mounted. A token rejects late results after refresh or disposal. No timer,
-- observation or background loop exists: a finished scan or page asks once.
local Model = require("data.model")
local Inventories = require("apps.diskmap.models.Inventories")
local Applications = require("apps.diskmap.models.Applications")
local Projects = require("apps.diskmap.models.Projects")
local Catalog = require("apps.diskmap.Catalog")
local Xcode = require("apps.diskmap.helpers.Xcode")
local SimulatorService = require("apps.diskmap.services.Simulators")
local Service = {}; Service.__index = Service

function Service.new(service, changed, generation)
	return setmetatable({service = service, changed = changed, generation = generation, tokens = {}}, Service)
end

function Service:load(id, force)
	local stock = Inventories:state(id)
	local scan = self.generation()
	if not force and stock.scan == scan and (stock.loaded or stock.busy) then return end
	stock.scan, stock.busy = scan, true
	local token = (self.tokens[id] or 0) + 1
	self.tokens[id] = token
	local function current() return not self.closed and self.tokens[id] == token and self.generation() == scan end
	local function done()
		if not current() then return end
		stock.busy, stock.loaded = false, true
		self.changed()
	end
	self[id](self, stock, current, done)
end

function Service:applications(stock, current, done)
	local paths = {}
	for _, bundle in ipairs(Applications:all()) do table.insert(paths, bundle.path) end
	stock.pending = 2
	local function finish()
		if not current() then return end
		stock.pending = stock.pending - 1
		if stock.pending == 0 then done() else self.changed() end
	end
	self.service.applicationInfo(paths, function(info)
		if not current() then return end
		Model.db.applicationInfo = info; finish()
	end)
	self.service.installedBundleIds(function(ids)
		if not current() then return end
		Model.db.installedBundleIds = ids; finish()
	end)
end

function Service:simulators(stock, current, done)
	local pending = 2
	stock.error, stock.deviceError, stock.runtimeError = nil, nil, nil
	local function finish()
		if not current() then return end
		pending = pending - 1
		if pending > 0 then return end
		stock.loaded = true
		Inventories:simulatorPlan()
		done()
	end
	self.service.simulatorRuntimes(function(value, error)
		if not current() then return end
		stock.runtimeList, stock.runtimeError = value, error
		finish()
	end)
	self.service.simulatorDevices(function(listed, error)
		if not current() then return end
		stock.deviceError = error
		local ok, inventory = pcall(SimulatorService.discover, self.service, Model.db.home, listed)
		if not ok then stock.error = "Simulator folders could not be read."; finish(); return end
		stock.inventory = inventory
		local paths, slots = {}, {}
		for _, devices in pairs(inventory.devices or {}) do
			for _, device in ipairs(devices) do
				if device.dataPathSize == nil and device.measurePath then
					table.insert(paths, device.measurePath); table.insert(slots, device)
				end
			end
		end
		if #paths == 0 then finish(); return end
		self.service.measure(paths, function(sizes)
			if not current() then return end
			for index, device in ipairs(slots) do device.dataPathSize = sizes[index] end
			finish()
		end)
	end)
end

function Service:worktrees(stock, current, done)
	local roots = Catalog.projectRoots(Model.db.home, Model.db.projectRoots, false)
	self.service.worktreeScan(roots, function(entries, facts)
		if not current() then return end
		stock.entries, stock.facts, stock.progress = entries or {}, facts or {}, nil
		local repositories, count = {}, 0
		for _, entry in ipairs(stock.entries) do
			if entry.commonDir and not repositories[entry.commonDir] then repositories[entry.commonDir] = true; count = count + 1 end
		end
		stock.repositories = count
		Inventories:rebuildWorktrees()
		done()
	end, function(completed, total)
		if not current() then return end
		stock.progress = "Reading worktree evidence: " .. completed .. " of " .. total .. " done."
		if not stock.loaded then self.changed() end
	end)
end

function Service:projects(stock, current, done)
	Model.db.projectInfo = Model.db.projectInfo or {}
	local queue = {}
	for _, group in ipairs(Projects:groups(Projects.filters[1])) do
		if not Model.db.projectInfo[group.path] then table.insert(queue, group.path) end
	end
	local function step(index)
		if not current() then return end
		if index > #queue then done(); return end
		self.service.projectInfo(queue[index], function(info)
			if not current() then return end
			Model.db.projectInfo[queue[index]] = info or {loaded = true}
			step(index + 1)
		end)
	end
	step(1)
end

function Service:xcode(stock, current, done)
	local service = self.service
	local support, derived, archives = {}, {}, {}
	for _, root in ipairs(Xcode.deviceSupport) do
		for _, child in ipairs(service.children(root.path)) do
			table.insert(support, {platform = root.platform, name = child.name, path = child.path, bytes = child.bytes})
		end
	end
	for _, child in ipairs(service.children(Xcode.derivedData)) do
		local plist = service.readPropertyList(child.path .. "/info.plist")
		local workspace = type(plist) == "table" and plist.WorkspacePath or nil
		local exists
		if workspace then exists = service.exists(workspace) == true end
		table.insert(derived, {name = child.name, path = child.path, bytes = child.bytes, workspace = workspace, exists = exists})
	end
	for _, day in ipairs(service.children(Xcode.archives)) do
		for _, archive in ipairs(service.children(day.path)) do
			if archive.name:match("%.xcarchive$") then
				table.insert(archives, {name = archive.name, path = archive.path, bytes = archive.bytes, date = day.name,
					plist = service.readPropertyList(archive.path .. "/Info.plist")})
			end
		end
	end
	local function build()
		stock.rows = {support = Xcode.supportRows(support), derived = Xcode.derivedRows(derived), archives = Xcode.archiveRows(archives)}
		done()
	end
	local pending, paths = {}, {}
	for _, list in ipairs({support, derived, archives}) do
		for _, entry in ipairs(list) do
			if entry.bytes == nil then table.insert(paths, entry.path); table.insert(pending, entry) end
		end
	end
	if #paths == 0 then
		for _, entry in ipairs(pending) do entry.bytes = 0 end
		return build()
	end
	service.measure(paths, function(sizes)
		if not current() then return end
		for index, entry in ipairs(pending) do entry.bytes = sizes[index] or 0 end
		build()
	end)
end

function Service:refresh()
	for _, id in ipairs({"applications", "simulators", "worktrees", "xcode", "projects"}) do self:load(id) end
end

function Service:dispose()
	self.closed = true
end

return Service
