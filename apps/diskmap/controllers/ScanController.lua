local Inventory = require("apps.diskmap.models.Inventory")
local Scan = {}; Scan.__index = Scan
function Scan.new(model, service, home, changed)
	return setmetatable({model = model, service = service, home = home, changed = changed or function() end,
		generation = 0, status = "Preparing a complete storage inventory."}, Scan)
end
function Scan:notify() self.changed() end
function Scan:configure(cachePath, writeCache)
	self.cachePath = cachePath
	if cachePath then
		local data, err = self.service.readCache(cachePath)
		if data then
			Inventory.restore(self.model, data); self.disk = data.disk
			self.status = data.fixture and "Synthetic fixture · scanning and cleanup disabled" or "Saved scan · scanning and cleanup disabled"
			if not data.fixture and self.model.scan.completedAt then self.status = self.status .. " · " .. os.date("%d %b %H:%M", self.model.scan.completedAt) end
		else self.status = "Cache could not be loaded: " .. tostring(err) end
	else
		self.writeCache = writeCache or (self.service.defaultCachePath and self.service.defaultCachePath())
		self.disk = self.service.diskSpace(self.home)
		if self.writeCache and self.service.readCache then
			local data = self.service.readCache(self.writeCache)
			if data and not data.fixture then
				Inventory.restore(self.model, data)
				for _, m in pairs(self.model.measurements) do if m.bytes then m.status = "stale" end end
				self.status = "Previous scan · refreshing all categories"
			end
		end
	end
end
function Scan:cancel(silent)
	self.generation = self.generation + 1
	if self.job then self.job.cancelled = true; self.service.cancel(self.job); self.job = nil end
	if not silent then self.status = "Measurement cancelled; previous results retained."; self:notify() end
end
function Scan:start()
	if self.cachePath then return end
	self:cancel(true)
	local paths, ids, exclusions = Inventory.plan(self.model)
	if #paths == 0 then return end
	local ok, job = pcall(self.service.start, paths, exclusions)
	if not ok then self.status = "Could not start measurement: " .. tostring(job); self:notify(); return end
	self.job = job; self.status = "Measuring all storage categories…"; self:notify()
	local generation = self.generation
	self.service.await(job, function(result)
		if generation ~= self.generation then return end
		self.job = nil; Inventory.apply(self.model, ids, result)
		self.disk = self.service.diskSpace(self.home)
		self.status = result.failure and result.failure ~= "" and result.failure or "Measured " .. os.date("%H:%M") .. " · " .. (result.errors or 0) .. " unavailable locations"
		if self.writeCache and self.service.writeCache then
			local saved, err = self.service.writeCache(self.writeCache, Inventory.snapshot(self.model, self.disk))
			if not saved then self.status = self.status .. " · Cache not saved: " .. tostring(err) end
		end
		self:notify()
	end, function(progress)
		if generation ~= self.generation or not progress or not progress.total then return end
		self.status = string.format("Measuring all categories · %d/%d locations", progress.completed, progress.total)
		self:notify()
	end)
end
function Scan:dispose() self:cancel(true) end
return Scan
