local Page = require("apps.diskmap.controllers.PageController")
local Overview = require("apps.diskmap.models.Overview")
local Categories = require("apps.diskmap.models.Categories")
local Inventory = require("apps.diskmap.models.Inventory")
local Selection = require("apps.diskmap.models.Selection")
local Sectors = require("ui.sectors")
local Controller = Page.extend("overview", "Overview")

-- The overview lists every largest item that fits a glance; the Largest Items
-- page shows the full ranking.
local LARGEST = {preview = 6}

-- `handlers` routes user intent back to the root controller: open(id) opens a
-- category or resource, reclaim() the Clean Up page, access() privacy settings,
-- navigate(id) another sidebar destination, map(id) the Map inside a category
-- (or the whole map), menu(id) a resource's actions and changes() the full
-- list of changes since the snapshot.
function Controller.new(model, handlers)
	return setmetatable({model = model, handlers = handlers}, Controller)
end

function Controller:mount(host, state)
	local handlers = self.handlers
	local refs = self:attach(host, {status = state.status, actions = {
		access = function() handlers.access() end,
		-- A selected category points at its sector, as hovering it would.
		select = function(_, _, row)
			if not row then return end
			self.selectedId = row.id
			local chart = self.hero and self.hero.refs and self.hero.refs.chart
			if chart then Sectors.highlight(chart, row.id) end
		end,
		open = function(_, _, row) if row then handlers.open(row.id) end end,
		largestMenu = function(_, _, row) return handlers.menu(row.id) end,
		openLargest = function(_, _, row) if row then handlers.open(row.id) end end,
		showLargest = function() handlers.navigate("largest") end,
	}})
	self.hero = self.template:child("hero", "apps/diskmap/views/Hero.etlua")
	self.changes = self.template:child("changes", "apps/diskmap/views/Changes.etlua")
	self.notMeasured = self.template:child("notMeasured", "apps/diskmap/views/NotMeasured.etlua")
	return refs
end

function Controller:update(state)
	local refs = self.refs
	if not refs then return end
	self.categoryRows = Overview.categories(self.model, state.disk, state.query)
	refs.results:replaceRows(self.categoryRows)
	-- Reloading rows drops the native selection; the token restores it.
	if Selection.index(self.categoryRows, self.selectedId) then Selection.show(refs.results, self.categoryRows, self.selectedId)
	else self.selectedId = nil end
	local largest = Overview.largest(self.model, state.disk, LARGEST.preview, state.query)
	refs.largest:replaceRows(largest)
	refs.largestSection.hidden = #largest == 0
	refs.coverage.text = Categories.coverage(self.model, state.disk)
	refs.status.text = state.status
	refs.access.hidden = state.mock == true
	refs.access.title = (self.model.scan.errors or 0) > 0 and "Review scan access…" or "Scan access…"
	local chart = Overview.chart(self.model, state.disk)
	local actions = {reclaim = function() self.handlers.reclaim() end}
	for _, item in ipairs(chart.legend) do
		if item.id ~= Overview.folded then
			actions["category_" .. item.id] = function() self.handlers.open(item.id) end
		end
	end
	-- The ring leads into the Map: a category's sector opens the Map inside
	-- it, the folded categories and the center open the whole map. Free and
	-- unattributed space have nothing inside to show. The sector under the
	-- pointer is named in the center, in place of the used total.
	local summary = Overview.summary(self.model, state.disk, state.capacity)
	local marks = {}
	for _, mark in ipairs(chart.marks) do marks[mark.id] = mark end
	actions.chartSelect = function(id)
		if id == Overview.folded then self.handlers.map("")
		elseif self.model.resources:find(id) then self.handlers.map(id) end
	end
	actions.chartCenter = function() self.handlers.map("") end
	actions.chartHover = function(id)
		local refs, mark = self.hero.refs, id and marks[id]
		if not refs then return end
		refs.usedTotal.text = mark and mark.size or summary.used
		refs.usedCaption.text = mark and mark.label or summary.caption
		-- The sector under the pointer selects its category row.
		self.selectedId = Selection.index(self.categoryRows, id) and id or nil
		Selection.show(self.refs and self.refs.results, self.categoryRows, self.selectedId)
	end
	local cloudBytes, cloudFiles = Inventory.cloud(self.model)
	self.hero:update({summary = summary, chart = chart,
		hidden = Overview.hidden(state.disk, state.capacity, state.snapshotCount, self.model.scan.errors, cloudBytes, cloudFiles,
			not self.model.includeMedia, Overview.protected(self.model, state.fullDiskAccess)),
		reclaim = Overview.reclaim(self.model), volumeName = state.volumeName, scanStatus = state.status, actions = actions})
	self.changes:update({changes = state.changes, actions = {showAllChanges = function() self.handlers.changes() end}})
	-- An empty section takes no place in the page, so it adds no spacing.
	refs.changes.hidden = state.changes == nil
	-- Everything no category holds, and why, once the scan has finished:
	-- mid-scan every category is still on its way.
	local unmeasured = summary.calculating and {items = {}} or Overview.unmeasured(self.model, state.disk,
		{fullDiskAccess = state.fullDiskAccess, diskAccess = state.diskAccess, snapshotCount = state.snapshotCount, mediaExcluded = not self.model.includeMedia})
	unmeasured.actions = {grantAccess = function() self.handlers.access() end, exploreFolders = function() self.handlers.navigate("filesystem") end}
	self.notMeasured:update(unmeasured)
	refs.notMeasured.hidden = #unmeasured.items == 0
end

function Controller:dispose()
	self.hero, self.changes, self.notMeasured = nil, nil, nil
	Page.dispose(self)
end

return Controller
