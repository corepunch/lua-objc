local Model = require("data.model")
local Categories = require("apps.diskmap.models.Categories")
local Figures = require("apps.diskmap.models.Overview")
local Inventory = require("apps.diskmap.models.Inventory")
local Selection = require("apps.diskmap.models.Selection")
local Sectors = require("ui.sectors")

-- The Overview page: the disk's ring and legend, what changed, what could not
-- be measured, the categories and the largest items. Everything is drawn from
-- `data` once the scan has finished. The sector under the pointer is named on
-- the line under the ring and no list row follows it; a selected category row
-- points at its sector.
local Overview = Model.define({id = "overview", needs = {"map"}})

-- The overview lists every largest item that fits a glance; the Largest Items
-- page shows the full ranking.
local PREVIEW = {largest = 6}

-- Every action navigates or points, so none draws the page again. A legend
-- row's button is named for its category (`category_developer`).
Overview.queries = setmetatable({}, {__index = function() return true end})
Overview.__index = function(self, key)
	local value = Overview[key]
	if value ~= nil then return value end
	local id = tostring(key):match("^category_(.+)$")
	if id and id ~= Figures.folded then return function() self.services.open(id) end end
end

function Overview.new(needs, services)
	return setmetatable({storage = services.model, services = services, map = needs.map}, Overview)
end

function Overview:access() self.services.access() end
function Overview:reclaim() self.services.show("cleanup") end
function Overview:showLargest() self.services.show("largest") end
function Overview:showAllChanges() self.services.openChanges() end
function Overview:exploreFolders() self.services.show("filesystem") end
Overview.grantAccess = Overview.access

function Overview:open(_, _, row) if row then self.services.open(row.id) end end
Overview.openLargest = Overview.open

function Overview:largestMenu(_, _, row) return self.services.actions:resource(row.id) end

-- A selected category points at its sector, as hovering it would.
function Overview:select(_, _, row)
	if not row then return end
	self.selectedId = row.id
	if self.refs then Sectors.highlight(self.refs.chart, row.id) end
end

-- The ring leads into the Map: a category's sector opens the Map inside it,
-- the folded categories and the center open the whole map. Free and
-- unattributed space have nothing inside to show.
function Overview:showMap(id)
	self.map:setFocus(id)
	self.services.show("map")
end

function Overview:chartSelect(id)
	if id == Figures.folded then self:showMap("")
	elseif self.storage.resources:find(id) then self:showMap(id) end
end

function Overview:chartCenter() self:showMap("") end

function Overview:chartHover(id)
	local mark = id and self.marks[id]
	if self.refs then self.refs.chartDetail.text = mark and mark.detail or "" end
end

function Overview:data(state)
	local storage, disk = self.storage, state.disk
	local errors = storage.scan.errors or 0
	-- While the scan runs nothing is measured yet as far as this page shows:
	-- the ring is empty, the lists are absent, and everything is drawn when
	-- the scan finishes.
	local scanning = storage.scan.running == true
	local chart = scanning and {marks = {}, legend = {}, explanation = "Diskmap is measuring your storage. Sizes appear when it finishes."}
		or Figures.chart(storage, disk)
	self.marks, self.categoryRows = {}, {}
	for _, mark in ipairs(chart.marks) do self.marks[mark.id] = mark end
	local data = {status = state.status, accessHidden = state.mock == true, accessTitle = errors > 0 and "Review scan access…" or "Scan access…",
		hero = {summary = Figures.summary(storage, disk, state.capacity), chart = chart, volumeName = state.volumeName}}
	if scanning then return data end
	data.measured = true
	self.categoryRows = Figures.categories(storage, disk, state.query)
	if not Selection.index(self.categoryRows, self.selectedId) then self.selectedId = nil end
	local largest = Figures.largest(storage, disk, PREVIEW.largest, state.query)
	local cloudBytes, cloudFiles = Inventory.cloud(storage)
	local hero = data.hero
	hero.hiddenSpace = Figures.hidden(disk, state.capacity, state.snapshotCount, errors, cloudBytes, cloudFiles,
		not storage.includeMedia, Figures.protected(storage, state.fullDiskAccess))
	hero.reclaim = Figures.reclaim(storage, self.services.cleanupSources())
	data.coverage, data.largestHidden, data.changes = Categories.coverage(storage, disk), #largest == 0, state.changes
	-- Everything no category holds, and why.
	data.unmeasured = Figures.unmeasured(storage, disk, {fullDiskAccess = state.fullDiskAccess, diskAccess = state.diskAccess,
		snapshotCount = state.snapshotCount, mediaExcluded = not storage.includeMedia})
	data.lists = {results = self.categoryRows, largest = largest}
	return data
end

-- Reloading rows drops the native selection, which the token restores.
function Overview:rendered(refs)
	self.refs = refs
	Selection.show(refs.results, self.categoryRows, self.selectedId)
end

function Overview:deactivate() self.refs = nil end

return Overview
