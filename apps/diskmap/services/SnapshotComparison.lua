local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local ns = require("AppKit")
local Store = require("apps.diskmap.Store")
local Snapshot = require("apps.diskmap.helpers.Snapshot")
local Comparison = {}; Comparison.__index = Comparison

-- Compares live scans with a saved snapshot (the sheet that lists every change
-- is pages/sheets/SnapshotChanges.lua). The snapshot is measured once
-- with the live catalog — the same plan a live scan measures — and its
-- per-location totals are cached against the snapshot's creation time, so
-- later launches compare without decoding it again. Decoding yields every
-- `yieldEvery` records so the window keeps drawing.
--
-- `options`: path (the snapshot), cache (false for a one-off comparison),
-- measure(path, liveModel, yield) → totals, createdAt (injected by tests),
-- async(fn) and yield() (the run-loop primitives), changed(changes, failure).
local SNAPSHOT = {yieldEvery = 25000, headerSize = 72}

local function little64(bytes, offset)
	local value = 0
	for index = 7, 0, -1 do value = value * 256 + bytes:byte(offset + index) end
	return value
end

-- The snapshot's creation time, read from its uncompressed header, or nil
-- when the file is missing or not a snapshot.
function Comparison.created(path)
	local file = path and io.open(path, "rb")
	if not file then return nil end
	local header = file:read(SNAPSHOT.headerSize)
	file:close()
	if not header or #header < SNAPSHOT.headerSize or header:sub(1, 8) ~= "DMOCK002" then return nil end
	local created = little64(header, 57)
	return created > 0 and created or nil
end

-- The snapshot is measured with the live model's catalog, including the
-- locations the live scan discovered; otherwise a discovered app would read
-- as a change in the residual "Other files" row that no longer contains it.
local function measureSnapshot(path, live, yield)
	local Mock = require("apps.diskmap.services.Mock")
	local ScanController = require("apps.diskmap.services.Scan")
	local home = live.home
	Model.bind(live)
	local discovered = Locations:added()
	-- The snapshot's own store while it is measured; the window's code that
	-- runs while the measurement yields binds its own, so each step here
	-- binds this one again, and the live store is bound when it is done.
	local model = Store.new(home)
	local service = Mock.new({fixturePath = path, home = home, yieldEvery = SNAPSHOT.yieldEvery,
		yield = yield and function() yield(); Model.bind(model) end})
	for _, added in ipairs(discovered) do
		if not Locations:find(added.definition.id) then Locations:add(added.parentId, added.definition) end
	end
	local scan = ScanController.new(model, service, home)
	scan:start()
	local totals = Locations:totals()
	Model.bind(live)
	return totals, service.fixture.createdAt
end

function Comparison.new(model, service, options)
	options = options or {}
	return setmetatable({model = model, service = service, path = options.path,
		cache = options.cache ~= false, measure = options.measure or measureSnapshot,
		async = options.async or ns.async, yield = options.yield or function() ns.sleep(0) end,
		changed = options.changed or function() end}, Comparison)
end

-- The cached baseline, when it belongs to the snapshot on disk.
function Comparison:cached(createdAt)
	if not self.cache then return nil end
	local load = self.service.loadSnapshotSummary
	local baseline = Snapshot.decode(load())
	return baseline and baseline.createdAt == createdAt and baseline or nil
end

-- Measures the snapshot when needed, then reports the changes since it.
-- A missing or unreadable snapshot reports nothing.
function Comparison:compare()
	if self.closed then return end
	local createdAt = Comparison.created(self.path)
	if not createdAt then self.baseline = nil; self.result = nil; return end
	local baseline = self.baseline and self.baseline.createdAt == createdAt and self.baseline or self:cached(createdAt)
	if baseline then
		self.baseline = baseline
		self:report()
		return
	end
	if self.measuring then return end
	self.measuring = true
	self.async(function()
		local ok, totals, created = pcall(self.measure, self.path, self.model, self.yield)
		if self.closed then return end
		self.measuring = false
		if not ok then self.result = nil; self.changed(nil, tostring(totals)); return end
		self.baseline = {createdAt = created or createdAt, totals = totals}
		local save = self.service.saveSnapshotSummary
		if self.cache then save(Snapshot.encode(self.baseline)) end
		self:report()
	end)
end

function Comparison:dispose() self.closed = true end

function Comparison:report()
	self.result = Locations:changesSince(self.baseline)
	self.changed(Snapshot.overview(self.result))
end

return Comparison
