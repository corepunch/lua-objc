local ns = require("AppKit")
local Template = require("ui.template")
local Overview = require("apps.diskmap.models.Overview")
local Inventory = require("apps.diskmap.models.Inventory")
local Controller = {}; Controller.__index = Controller

-- The overview lists every largest item that fits a glance; the Largest Items
-- page shows the full ranking.
local LARGEST = {preview = 6}

-- `handlers` routes user intent back to the root controller: open(id) opens a
-- category, reclaim() the Clean Up page, access() privacy settings,
-- navigate(id) another sidebar destination, menu(id) a resource's actions and
-- changes() the full list of changes since the snapshot.
function Controller.new(model, categories, handlers)
	return setmetatable({model = model, categories = categories, handlers = handlers}, Controller)
end

function Controller:mount(host, state)
	local handlers = self.handlers
	self.template = Template.new(host, "apps/diskmap/views/Overview.etlua", ns)
	local _, refs = self.template:update({status = state.status, actions = {
		access = function() handlers.access() end,
		select = function(_, _, row) if row then self.selectedId = row.id end end,
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
	refs.results:replaceRows(Overview.categories(self.model, state.disk, state.query))
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
	local cloudBytes, cloudFiles = Inventory.cloud(self.model)
	self.hero:update({summary = Overview.summary(self.model, state.disk, state.capacity), chart = chart,
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
