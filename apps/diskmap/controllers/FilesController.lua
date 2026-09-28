local ns = require("AppKit")
local Template = require("ui.template")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Inventory = require("apps.diskmap.models.Inventory")
local Controller = {}; Controller.__index = Controller

-- Large Files: the individual files the last scan ranked, with filters for
-- files unused for a year, installers and media. `actions` builds row menus.
function Controller.new(model, service, actions)
	return setmetatable({model = model, service = service, actions = actions, filterIndex = 1}, Controller)
end

-- File Types opens this page narrowed to one kind.
function Controller:focus(kind)
	self.kind, self.filterIndex = kind, Files.filterIndex("All")
end

function Controller:mount(host, state)
	self.template = Template.new(host, "apps/diskmap/views/Files.etlua", ns)
	local _, refs = self.template:update({filters = Files.filters, threshold = Model.size(Inventory.summary.minimumFileBytes), actions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:update(self.state) end,
		clearKind = function() self.kind = nil; self:update(self.state) end,
		rowMenu = function(_, _, row) return self.actions:file(row) end,
		reveal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	self.refs = refs
	self:update(state)
	return refs
end

function Controller:update(state)
	self.state = state
	local refs = self.refs
	if not refs then return end
	refs.filter.selectedSegment = self.filterIndex - 1
	local filter = Files.filters[self.filterIndex]
	local rows = Files.rows(self.model, filter, state and state.query, self.kind)
	refs.files:replaceRows(rows)
	-- An empty list says why it is empty: nothing matches the search, or
	-- this filter has no files.
	local query = state and state.query or ""
	local measured = self.model.files ~= nil
	refs.filesPanel.hidden = measured and #rows == 0
	refs.filesEmpty.hidden = not (measured and #rows == 0 and query == "")
	refs.filesNoResults.hidden = not (measured and #rows == 0 and query ~= "")
	local summary = Files.summary(self.model)
	local kind = self.kind and Files.kindById(self.kind)
	refs.clearKind.hidden = kind == nil
	refs.filterDetail.text = (kind and (kind.name .. " · ") or "") .. Model.plural(Model.count(#rows), "file")
		.. (filter == "Unused for a year" and " not opened or changed in a year" or "")
		.. (filter == "Yours" and " you can move to the Trash" or "")
		.. (query ~= "" and " matching the search" or "")
	if not summary then
		refs.summary.text = "Measuring files… Large files appear when the scan finishes."
		return
	end
	refs.summary.text = string.format("%s over %s use %s%s.", Model.plural(Model.count(summary.count), "file"), Model.size(Inventory.summary.minimumFileBytes),
		Model.size(summary.bytes), summary.partial and " · some locations could not be read" or "")
	refs.largeTileValue.text = Model.size(summary.bytes)
	refs.largeTileDetail.text = Model.plural(Model.count(summary.count), "file") .. ", largest first"
	refs.oldTileValue.text = Model.size(summary.oldBytes)
	refs.oldTileDetail.text = Model.plural(Model.count(summary.oldCount), "file") .. " not opened or changed in a year"
	refs.movableTileValue.text = Model.size(summary.reviewableOldBytes)
	refs.movableTileDetail.text = Model.plural(Model.count(summary.reviewableOld), "unused document") .. " you can move to the Trash"
end

function Controller:dispose()
	if self.template then self.template:dispose() end
	self.template, self.refs = nil, nil
end

return Controller
