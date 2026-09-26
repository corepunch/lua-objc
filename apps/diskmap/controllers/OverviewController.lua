local ns = require("AppKit")
local Template = require("ui.template")
local Overview = require("apps.diskmap.models.Overview")
local Controller = {}; Controller.__index = Controller

-- The overview lists every largest item that fits a glance; the Largest Items
-- page shows the full ranking.
local LARGEST = {preview = 6}

-- `handlers` routes user intent back to the root controller: open(id) opens a
-- category, reclaim() the cleanup sheet, access() privacy settings, and
-- navigate(id) another sidebar destination.
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
		selectLargest = function(_, _, row) if row then self.selectedId = row.id end end,
		openLargest = function(_, _, row) if row then handlers.open(row.parentId) end end,
		showLargest = function() handlers.navigate("largest") end,
	}})
	self.refs = refs
	self.hero = self.template:child("hero", "apps/diskmap/views/Hero.etlua")
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
	self.hero:update({summary = Overview.summary(self.model, state.disk), chart = chart,
		reclaim = Overview.reclaim(self.model), volumeName = state.volumeName, actions = actions})
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.hero, self.refs = nil, nil, nil
end

return Controller
