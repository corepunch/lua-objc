local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Overview = require("apps.diskmap.models.Overview")
local Controller = {}; Controller.__index = Controller

-- The ranking stops where individual items stop mattering at a glance; the
-- category sheets still list everything.
local LARGEST = {limit = 100}

-- `open(id)` opens the category that owns a resource.
function Controller.new(model, service, open)
	return setmetatable({model = model, service = service, open = open}, Controller)
end

function Controller:mount(host)
	self.template = Template.new(host, "apps/diskmap/views/Largest.etlua", ns)
	local _, refs = self.template:update({summary = "", actions = {
		selectLargest = function(_, _, row) self:select(row) end,
		openLargest = function(_, _, row) if row then self.open(row.parentId) end end,
		reveal = function() if self.selected and self.selected.path then self.service.reveal(self.selected.path) end end,
		openCategory = function() if self.selected then self.open(self.selected.parentId) end end,
	}})
	self.refs = refs
	return refs
end

function Controller:select(row)
	self.selected = row
	if not self.refs then return end
	self.refs.reveal.enabled = row ~= nil and row.path ~= nil
	self.refs.openCategory.enabled = row ~= nil
	self.refs.selection.text = row and (row.path or row.subtitle) or ""
end

function Controller:update(state)
	if not self.refs then return end
	local rows = Overview.largest(self.model, state.disk, LARGEST.limit, state.query)
	self.refs.largest:replaceRows(rows)
	local bytes = 0
	for _, row in ipairs(rows) do bytes = bytes + row.bytes end
	self.refs.largestSummary.text = #rows == 0 and "No measured items match yet."
		or string.format("The %d largest measured items use %s.", #rows, Model.size(bytes))
	self:select(nil)
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs, self.selected = nil, nil, nil
end

return Controller
