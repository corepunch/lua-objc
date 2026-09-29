local ns = require("AppKit")
local Template = require("ui.template")
local Overview = require("apps.diskmap.models.Overview")
local Inventory = require("apps.diskmap.models.Inventory")
local Selection = require("apps.diskmap.models.Selection")
local Sectors = require("ui.sectors")
local Controller = {}; Controller.__index = Controller

-- The overview lists every largest item that fits a glance; the Largest Items
-- page shows the full ranking.
local LARGEST = {preview = 6}

-- `handlers` routes user intent back to the root controller: open(id) opens a
-- category, reclaim() the Clean Up page, access() privacy settings,
-- navigate(id) another sidebar destination, map(id) the Map inside a category
-- (or the whole map), menu(id) a resource's actions and changes() the full
-- list of changes since the snapshot.
function Controller.new(model, categories, handlers)
	return setmetatable({model = model, categories = categories, handlers = handlers}, Controller)
end

function Controller:mount(host, state)
	local handlers = self.handlers
	self.template = Template.new(host, "apps/diskmap/views/Overview.etlua", ns)
	local _, refs = self.template:update({status = state.status, actions = {
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
		openLargest = function(_, _, row) if row then handlers.open(row.parentId) end end,
		showLargest = function() handlers.navigate("largest") end,
	}})
	self.refs = refs
	self.hero = self.template:child("hero", "apps/diskmap/views/Hero.etlua")
	self.changes = self.template:child("changes", "apps/diskmap/views/Changes.etlua")
	self.access = self.template:child("accessNotice", "apps/diskmap/views/AccessNotice.etlua")
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
	refs.coverage.text = self.categories:coverage(state.disk)
	refs.status.text = state.status
	refs.access.hidden = state.mock == true
	refs.access.title = (self.model.scan.errors or 0) > 0 and "Review scan access…" or "Scan access…"
	local chart = Overview.chart(self.model, state.disk)
	local actions = {reclaim = function() self.handlers.reclaim() end}
	for _, item in ipairs(chart.legend) do
		actions["category_" .. item.id] = function() self.handlers.open(item.id) end
	end
	-- The ring leads into the Map: a category's sector opens the Map inside
	-- it, the folded categories and the center open the whole map. Free and
	-- unattributed space have nothing inside to show. The sector under the
	-- pointer is named in the center, in place of the used total.
	local summary = Overview.summary(self.model, state.disk, state.capacity)
	local marks = {}
	for _, mark in ipairs(chart.marks) do marks[mark.id] = mark end
	actions.chartSelect = function(id)
		if id == "other" then self.handlers.map("")
		elseif self.model.resources:find(id) then self.handlers.map(id) end
	end
	actions.chartCenter = function() self.handlers.map("") end
	actions.chartHover = function(id)
		local refs, mark = self.hero.refs, id and marks[id]
		if not refs then return end
		refs.usedTotal.text = mark and mark.size or summary.used
		refs.usedCaption.text = mark and mark.label or summary.caption
		-- The sector under the pointer selects its category row; the folded
		-- categories share a sector and have no row of their own.
		local category = mark and not mark.folded and id or nil
		self.selectedId = Selection.index(self.categoryRows, category) and category or nil
		Selection.show(self.refs and self.refs.results, self.categoryRows, self.selectedId)
	end
	local cloudBytes, cloudFiles = Inventory.cloud(self.model)
	self.hero:update({summary = summary, chart = chart,
		hidden = Overview.hidden(state.disk, state.capacity, state.snapshotCount, self.model.scan.errors, cloudBytes, cloudFiles,
			not self.model.includeMedia),
		reclaim = Overview.reclaim(self.model), volumeName = state.volumeName, actions = actions})
	self.changes:update({changes = state.changes, actions = {showAllChanges = function() self.handlers.changes() end}})
	-- An empty section takes no place in the page, so it adds no spacing.
	refs.changes.hidden = state.changes == nil
	-- Folders the scan could not read, while Full Disk Access is missing.
	local unreadable = state.fullDiskAccess == false and Overview.unreadable(self.model) or {paths = {}, more = 0, moreText = "0"}
	self.access:update({unreadable = unreadable, actions = {grantAccess = function() self.handlers.access() end}})
	refs.accessNotice.hidden = #unreadable.paths == 0
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.hero, self.changes, self.access, self.refs = nil, nil, nil, nil, nil
end

return Controller
