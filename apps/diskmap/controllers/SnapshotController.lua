local ns = require("AppKit")
local xml = require("ui.xml")
local Sheet = require("apps.diskmap.Sheet")
local Model = require("apps.diskmap.Model")
local Snapshot = require("apps.diskmap.models.Snapshot")
local Controller = {}; Controller.__index = Controller

-- Compares live scans with a saved snapshot. The snapshot is measured once
-- with the live catalog — the same plan a live scan measures — and its
-- per-location totals are cached against the snapshot's creation time, so
-- later launches compare without decoding it again. Decoding yields every
-- `yieldEvery` records so the window keeps drawing.
--
-- `options`: path (the snapshot), cache (false for a one-off comparison),
-- measure(path, liveModel, yield) → totals, createdAt (injected by tests),
-- async(fn) and yield() (the run-loop primitives), changed(changes, failure).
local SNAPSHOT = {yieldEvery = 25000}

-- The snapshot is measured with the live model's catalog, including the
-- locations the live scan discovered; otherwise a discovered app would read
-- as a change in the residual "Other files" row that no longer contains it.
local function measureSnapshot(path, live, yield)
	local Mock = require("apps.diskmap.services.Mock")
	local ScanController = require("apps.diskmap.controllers.ScanController")
	local home = live.home
	local service = Mock.new({fixturePath = path, home = home, yield = yield, yieldEvery = SNAPSHOT.yieldEvery})
	local model = Model.new(home)
	for _, added in ipairs(live.resources:added()) do
		if not model.resources:find(added.definition.id) then model.resources:add(added.parentId, added.definition) end
	end
	local scan = ScanController.new(model, service, home)
	scan:start()
	return Snapshot.totals(model), service.fixture.createdAt
end

function Controller.new(model, service, actions, options)
	options = options or {}
	return setmetatable({model = model, service = service, actions = actions, path = options.path,
		cache = options.cache ~= false, measure = options.measure or measureSnapshot,
		async = options.async or ns.async, yield = options.yield or function() ns.sleep(0) end,
		changed = options.changed or function() end}, Controller)
end

-- The cached baseline, when it belongs to the snapshot on disk.
function Controller:cached(createdAt)
	if not self.cache then return nil end
	local load = rawget(self.service, "loadSnapshotSummary")
	local baseline = load and Snapshot.decode(load())
	return baseline and baseline.createdAt == createdAt and baseline or nil
end

-- Measures the snapshot when needed, then reports the changes since it.
-- A missing or unreadable snapshot reports nothing.
function Controller:compare()
	local createdAt = Snapshot.created(self.path)
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
		self.measuring = false
		if not ok then self.result = nil; self.changed(nil, tostring(totals)); return end
		self.baseline = {createdAt = created or createdAt, totals = totals}
		local save = rawget(self.service, "saveSnapshotSummary")
		if self.cache and save then save(Snapshot.encode(self.baseline)) end
		self:report()
	end)
end

function Controller:report()
	self.result = Snapshot.changes(self.model, self.baseline)
	self.changed(Snapshot.overview(self.result))
end

-- Every change, in a sheet over the window.
function Controller:open(parent)
	if not self.result then return end
	self:close()
	self.sheet, self.refs = Sheet.present(function()
		return xml.renderFile("apps/diskmap/views/SnapshotChanges.etlua", {title = self.result.title, detail = self.result.detail,
			actions = {
				done = function() self:close() end,
				rowMenu = function(_, _, row) return row and self.actions:resource(row.id) or {} end,
				reveal = function(_, _, row) if row and row.path then self.actions:reveal(row.path) end end,
			}}, ns)
	end, parent)
	if self.refs then self.refs.changes:replaceRows(self.result.rows) end
end

function Controller:close()
	if self.sheet then ns.dismiss(self.sheet) end
	self.sheet, self.refs = nil, nil
end

return Controller
