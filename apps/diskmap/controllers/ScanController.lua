local Inventory = require("apps.diskmap.models.Inventory")
local Scan = {}; Scan.__index = Scan
function Scan.new(model, service, home, changed)
	return setmetatable({model = model, service = service, home = home, changed = changed or function() end,
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
	local function measure()
		if generation ~= self.generation then return end
		local paths, ids, exclusions = Inventory.plan(self.model)
		if #paths == 0 then return end
		Inventory.begin(self.model, ids)
		local ok, job = pcall(self.service.start, paths, exclusions)
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
			self.status = result.failure and result.failure ~= "" and result.failure or "Measured " .. os.date("%H:%M") .. " · finished in " .. elapsed
			self:notify()
		end, function(progress)
			if generation ~= self.generation or type(progress) ~= "table" or type(progress.total) ~= "number" or progress.total <= 0 then return end
			Inventory.progress(self.model, ids, progress)
			local completed = math.min(progress.completed or 0, progress.total)
			local percent = math.floor(completed * 100 / progress.total)
			self.status = string.format("Scanning %d of %d locations (%d%%)", completed, progress.total, percent)
			self:notify()
		end)
	end
	if rawget(self.service, "discoverEntries") then
		local _, initialIds = Inventory.plan(self.model)
		Inventory.begin(self.model, initialIds)
		self.status = "Discovering project build data and installers…"; self:notify()
		self.service.discoverEntries(self.home, function(entries)
			if generation ~= self.generation then return end
			local known = {}
			for _, row in ipairs(self.model.resources:leaves()) do if row.path then known[row.path] = true end end
			for _, entry in ipairs(entries or {}) do
				if not known[entry.path] then
					local _, err = self.model.resources:add(entry.parentId or (entry.path:match("^/Applications/") and "applications" or "developer"), entry)
					if err then self.status = "Could not register discovered resource: " .. err.message; self:notify(); return end
					known[entry.path] = true
				end
			end
			measure()
		end)
	else
		measure()
	end
end
function Scan:dispose() self:cancel(true) end
return Scan
