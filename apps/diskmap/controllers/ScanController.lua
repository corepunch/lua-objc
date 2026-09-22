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
	if rawget(self.service, "agentEntries") then
		require("apps.diskmap.models.AgentFiles").add(self.model, self.service.agentEntries(self.model))
	end
	local paths, ids, exclusions = Inventory.plan(self.model)
	if #paths == 0 then return end
	Inventory.begin(self.model, ids)
	local ok, job = pcall(self.service.start, paths, exclusions)
	if not ok then
		Inventory.apply(self.model, ids, {failure = tostring(job)})
		self.status = "Could not start measurement: " .. tostring(job); self:notify(); return
	end
	self.job = job; self.status = "Measuring all storage categories…"; self:notify()
	local generation = self.generation
	self.service.await(job, function(result)
		if generation ~= self.generation then return end
		self.job = nil; Inventory.apply(self.model, ids, result)
		self.disk = self.service.diskSpace(self.home)
		self.status = result.failure and result.failure ~= "" and result.failure or "Measured " .. os.date("%H:%M") .. " · " .. (result.errors or 0) .. " unavailable locations"
		self:notify()
	end, function(progress)
		if generation ~= self.generation or not progress or not progress.total then return end
		Inventory.progress(self.model, ids, progress)
		self.status = string.format("Measuring all categories · %d/%d locations", progress.completed, progress.total)
		self:notify()
	end)
end
function Scan:dispose() self:cancel(true) end
return Scan
