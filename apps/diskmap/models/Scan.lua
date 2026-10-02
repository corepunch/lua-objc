local Inventory = require("apps.diskmap.models.Inventory")
local Volumes = require("apps.diskmap.models.Volumes")
local Model = require("apps.diskmap.Model")
local Scan = {}; Scan.__index = Scan
-- `finished(result)` runs after each completed measurement, before pages
-- refresh, so callers can record history or remeasure related state.
function Scan.new(model, service, home, changed, finished)
	return setmetatable({model = model, service = service, home = home, changed = changed or function() end,
		finished = finished or function() end,
		generation = 0, status = "Preparing a complete storage inventory."}, Scan)
end
function Scan:notify() self.changed() end
function Scan:cancel(silent)
	self.generation = self.generation + 1
	if self.job then self.job.cancelled = true; self.service.cancel(self.job); self.job = nil end
	Inventory.cancel(self.model)
	if not silent then self.status = "Measurement cancelled; completed locations retained."; self:notify() end
end
function Scan:start()
	self:cancel(true)
	local generation = self.generation
	self.startedAt = os.time()
	if rawget(self.service, "agentEntries") then
		local added, err = require("apps.diskmap.models.AgentFiles").add(self.model, self.service.agentEntries(self.model))
		if not added then self.status = "Could not register discovered resource: " .. (err and err.message or "unknown error"); self:notify(); return end
	end
	-- Locations macOS keeps from every app are named, not walked.
	local protected = rawget(self.service, "protectedLocations")
	self.model.protected = protected and protected() or {}
	local function walk()
		local paths, ids, exclusions = Inventory.plan(self.model)
		if #paths == 0 then return end
		Inventory.begin(self.model, ids)
		local ok, job = pcall(self.service.start, paths, exclusions, Inventory.options())
		if not ok then
			Inventory.apply(self.model, ids, {failure = tostring(job)})
			self.status = "Could not start measurement: " .. tostring(job); self:notify(); return
		end
		self.job = job; self.status = "Measuring all storage categories…"; self:notify()
		self.service.await(job, function(result)
			if generation ~= self.generation then return end
			self.job = nil; Inventory.apply(self.model, ids, result)
			self.disk = self.service.diskSpace(self.home)
			local seconds = math.max(0, math.floor(result.seconds or (os.time() - self.startedAt)))
			local elapsed = seconds < 60 and (seconds .. " sec") or (math.floor(seconds / 60) .. " min " .. (seconds % 60) .. " sec")
			local label = (result.partial == true or (result.errors or 0) > 0) and "Partial lower bound" or "Measured"
			self.status = result.failure and result.failure ~= "" and result.failure or label .. " " .. os.date("%H:%M") .. " · finished in " .. elapsed
			self.finished(result)
			self:notify()
		end, function(progress)
			if generation ~= self.generation or type(progress) ~= "table" or type(progress.total) ~= "number" or progress.total <= 0 then return end
			Inventory.progress(self.model, ids, progress)
			local completed = math.min(progress.completed or 0, progress.total)
			-- Location counts are not an estimate of time remaining: the final
			-- location can hold more files than every earlier one combined.
			self.status = string.format("%d of %d locations measured · %s items checked · %d sec elapsed",
				completed, progress.total, Model.count(progress.visited or 0), math.floor(progress.seconds or 0))
			if type(progress.currentPath) == "string" and progress.currentPath ~= "" then
				self.status = self.status .. " · Measuring " .. Model.tilde(progress.currentPath, self.home)
			end
			self:notify()
		end)
	end
	-- APFS volume sizes are asked for at once, alongside discovery: they take
	-- a moment, discovery can take minutes, and the volumes should not wait
	-- on it. The walk starts once both are in. `volumeUsage` is {} when the
	-- provider cannot say, so pages know the answer is in.
	local usageReady, discovered = false, false
	local function measure()
		discovered = true
		if generation ~= self.generation or not usageReady then return end
		walk()
	end
	local apfs = rawget(self.service, "apfsVolumes")
	if apfs then
		apfs(function(list, container)
			if generation ~= self.generation then return end
			self.model.volumeUsage = Volumes.usage(list, container) or {}
			usageReady = true
			self:notify()
			if discovered then walk() end
		end)
	else
		self.model.volumeUsage, usageReady = {}, true
	end
	if rawget(self.service, "discoverEntries") then
		local _, initialIds = Inventory.plan(self.model)
		Inventory.begin(self.model, initialIds)
		self.status = "Discovering project build data and installers…"; self:notify()
		self.service.discoverEntries(self.home, function(entries)
			if generation ~= self.generation then return end
			local ok, err = Scan.register(self.model, entries)
			if not ok then self.status = "Could not register discovered resource: " .. err.message; self:notify(); return end
			measure()
		end, self.model.projectRoots)
	else
		measure()
	end
end
-- Registers discovered resources once each, however many searched roots
-- reached them. A project build folder (`artifact`) joins its ecosystem's
-- group under Developer ("Node modules"), created with its first folder, so
-- every page can show one total per ecosystem; the Projects page groups the
-- same leaves by project, so nothing is counted twice.
function Scan.register(model, entries)
	local Catalog = require("apps.diskmap.Catalog")
	local known = {}
	for _, row in ipairs(model.resources:leaves()) do if row.path then known[row.path] = true end end
	for _, entry in ipairs(entries or {}) do
		if not known[entry.path] then
			local parentId = entry.parentId or (entry.path:match("^/Applications/") and "applications" or "developer")
			local group = entry.artifact and parentId == "developer" and Catalog.buildGroup(entry.artifact)
			if group then
				local copy = {}
				for key, value in pairs(entry) do if key ~= "parentId" then copy[key] = value end end
				entry = copy
			end
			local _, err
			if group and not model.resources:find(group.id) then
				group.children = {entry}
				_, err = model.resources:add("developer", group)
			else
				_, err = model.resources:add(group and group.id or parentId, entry)
			end
			if err then return false, err end
			known[entry.path] = true
		end
	end
	return true
end
function Scan:dispose() self:cancel(true) end
return Scan
