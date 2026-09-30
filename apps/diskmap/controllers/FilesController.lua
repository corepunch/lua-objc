local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Inventory = require("apps.diskmap.models.Inventory")
local Controller = Page.extend("files")

local THRESHOLD = Model.size(Inventory.summary.minimumFileBytes)
local LAYOUT = {
	summary = "Measuring files…",
	tiles = {
		{id = "largeTile", icon = "doc.fill", color = "systemTeal", title = "Over " .. THRESHOLD, value = "—", detail = "Individual files, largest first"},
		{id = "oldTile", icon = "clock.fill", color = "systemOrange", title = "Unused for a year", value = "—", detail = "Not opened or changed since"},
		{id = "movableTile", icon = "trash.fill", color = "systemRed", title = "Yours to review", value = "—", detail = "Unused documents you can move to the Trash"},
	},
	sections = {{title = "Files", detailId = "filterDetail",
		links = {{id = "clearKind", title = "Show All Kinds", style = "link", action = "clearKind", hidden = true}},
		filters = {id = "filter", options = Files.filters},
		empties = {
			{id = "filesNoResults", hidden = true, title = "No Results", systemImage = "magnifyingglass", description = "No large file matches the search. The totals above count every large file."},
			{id = "filesEmpty", hidden = true, title = "No Files Here", systemImage = "doc", description = "No large file fits this filter. Choose All to see every file Diskmap ranked."},
		},
		panelId = "filesPanel",
		list = {id = "files", menu = "rowMenu", activate = "reveal", detailColumn = true, fileIcons = true}}},
	footnote = {text = "Diskmap reads only names, sizes and dates. Files inside apps, libraries and hidden tool folders are listed for context and managed by their owners; only your own documents can be moved to the Trash here."},
}

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
	local refs = self:attach(host, {layout = LAYOUT, actions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:update(self.state) end,
		clearKind = function() self.kind = nil; self:update(self.state) end,
		rowMenu = function(_, _, row) return self.actions:file(row) end,
		reveal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
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
	refs.summary.text = string.format("%s over %s use %s%s.", Model.plural(Model.count(summary.count), "file"), THRESHOLD,
		Model.size(summary.bytes), summary.partial and " · some locations could not be read" or "")
	refs.largeTileValue.text = Model.size(summary.bytes)
	refs.largeTileDetail.text = Model.plural(Model.count(summary.count), "file") .. ", largest first"
	refs.oldTileValue.text = Model.size(summary.oldBytes)
	refs.oldTileDetail.text = Model.plural(Model.count(summary.oldCount), "file") .. " not opened or changed in a year"
	refs.movableTileValue.text = Model.size(summary.reviewableOldBytes)
	refs.movableTileDetail.text = Model.plural(Model.count(summary.reviewableOld), "unused document") .. " you can move to the Trash"
end

return Controller
