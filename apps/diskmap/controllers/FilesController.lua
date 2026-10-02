local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Inventory = require("apps.diskmap.models.Inventory")
local Scope = require("apps.diskmap.models.Scope")
local Controller = Page.extend("files")

local THRESHOLD = Model.size(Inventory.summary.minimumFileBytes)
local LAYOUT = {
	summary = "Measuring files…", scopeNote = Scope.pages.files, leads = {"lead"}, contextAfterSections = true, contextDisclosure = "Scan scope and statistics",
	tiles = {
		{id = "largeTile", icon = "doc.fill", color = "systemTeal", title = "Over " .. THRESHOLD, value = "—", detail = "Individual files, largest first"},
		{id = "oldTile", icon = "clock.fill", color = "systemOrange", title = "Unused for a year", value = "—", detail = "Not opened or changed since"},
		{id = "movableTile", icon = "trash.fill", color = "systemRed", title = "Yours to review", value = "—", detail = "Unused documents you can move to the Trash"},
	},
	sections = {{
		controlsId = "fileControls",
		links = {{id = "clearKind", title = "Show All Kinds", style = "link", action = "clearKind", hidden = true}},
		filters = {id = "filter", options = Files.filters},
		empties = {
			{id = "filesUnavailable", hidden = true, title = "File Results Unavailable", systemImage = "exclamationmark.triangle", description = "Check scan access, then refresh to measure files again."},
			{id = "filesNone", hidden = true, title = "No Large Files Found", systemImage = "doc", description = "No files over " .. THRESHOLD .. " were ranked. Clean Up can still find rebuildable data."},
			{id = "filesNoResults", hidden = true, title = "No Results", systemImage = "magnifyingglass", description = "No large file matches the search. Try another filter or search."},
			{id = "filesEmpty", hidden = true, title = "No Files Here", systemImage = "doc", description = "No large file fits this filter. Choose All to see every file Diskmap ranked."},
		},
		panelId = "filesPanel",
		list = {id = "files", menu = "rowMenu", activate = "reveal", detailColumn = true, fileIcons = true}}},
	footnote = {text = "Diskmap reads only names, sizes and dates. Files inside apps, libraries and hidden tool folders are listed for context and managed by their owners; only your own documents can be moved to the Trash here."},
}

-- Large Files: the individual files the last scan ranked, with filters for
-- files unused for a year, installers and media. `actions` builds row menus.
function Controller.new(context)
	return setmetatable({model = context.model, service = context.service, actions = context.actions, filterIndex = 1}, Controller)
end

-- File Types opens this page narrowed to one kind.
function Controller:focus(kind)
	self.kind, self.filterIndex = kind, Files.filterIndex("All")
end

function Controller:mount(host, state)
	local refs = self:attach(host, {layout = LAYOUT, actions = {
		filter = function(index) self.filterIndex = (index or 0) + 1; self:update(self.state) end,
		clearKind = function() self.kind = nil; self:update(self.state) end,
		markFiles = function() self:markFiles() end,
		reviewMarked = function() self.actions.handlers.review() end,
		refreshFiles = function() self.actions.handlers.refresh() end,
		cleanup = function() self.actions.handlers.show("cleanup") end,
		clearSearch = function() self.actions.handlers.search("files", "") end,
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
	refs.scopeNote.text = Scope.text(self.model, "files")
	local filter = Files.filters[self.filterIndex]
	local fileState, stateReason = Files.state(self.model)
	local noLargeFiles = self.model.files ~= nil and #(self.model.files.large or {}) == 0 and #(self.model.files.old or {}) == 0 and fileState ~= "loading"
	local rows = Files.rows(self.model, filter, state and state.query, self.kind)
	self.visible = rows
	refs.files:replaceRows(self.actions:annotate(rows))
	local bytes, reviewable, marked, included = 0, 0, 0, 0
	for _, row in ipairs(rows) do
		bytes = bytes + row.bytes
		if Files.validateTrash(self.model, row.path) then
			if self.actions:isMarked(row.path) then marked = marked + 1
			elseif self.actions:isIncluded(row.path) then marked, included = marked + 1, included + 1
			else reviewable = reviewable + 1 end
		end
	end
	local kind = self.kind and Files.kindById(self.kind)
	local decision = {id = "decision", icon = "doc.fill", color = "systemTeal",
		title = (kind and kind.name or filter) .. " · " .. Model.plural(#rows, "file"),
		detail = filter == "Installers & archives" and "Check that these are installed or extracted. Marking stages them for your final review."
			or "Review the contents before marking. Files inside apps or libraries stay with their owners.",
		amount = Model.size(bytes), amountCaption = "to review",
		actionTitle = reviewable > 0 and ("Mark " .. Model.plural(reviewable, "File")) or (marked > 0 and "Review Marked Items…" or "No Files to Mark"),
		action = reviewable > 0 and "markFiles" or "reviewMarked", disabled = (reviewable == 0 and marked == 0) or self.model.scan.running,
		secondaryTitle = reviewable > 0 and marked > 0 and "Review Marked Items…" or nil, secondaryAction = "reviewMarked",
		actions = {
			markFiles = function() self:markFiles() end, reviewMarked = function() self.actions.handlers.review() end,
			refreshFiles = function() self.actions.handlers.refresh() end, cleanup = function() self.actions.handlers.show("cleanup") end,
			clearSearch = function() self.actions.handlers.search("files", "") end}}
	if included > 0 then decision.detail = Model.plural(included, "file") .. " included through a marked folder. Review the folder to change its cleanup plan." end
	if #rows == 0 and fileState == "loading" then
		decision.title, decision.detail = "Looking for large files…", "Results appear as they are measured. Marking is available after the scan finishes."
		decision.amount, decision.amountCaption, decision.actionTitle = "—", "in progress", nil
	elseif fileState == "empty" or (fileState == "loaded" and noLargeFiles) then
		decision.title, decision.detail = "No large files found", "No files over " .. THRESHOLD .. " were ranked. Review rebuildable data in Clean Up."
		decision.amount, decision.amountCaption, decision.actionTitle, decision.action = "—", "scan finished", "Open Clean Up", "cleanup"
		decision.disabled = false
	elseif fileState == "error" or fileState == "unavailable" then
		decision.title, decision.detail = "File results unavailable", stateReason
		decision.amount, decision.amountCaption, decision.actionTitle, decision.action = "—", "not measured", "Refresh Scan", "refreshFiles"
		decision.disabled = false
	elseif #rows == 0 and (state and state.query or "") ~= "" then
		decision.title, decision.detail = "Nothing matches this search", "Clear the search or choose another filter to review the measured files."
		decision.amount, decision.amountCaption, decision.actionTitle, decision.action = "—", "no matches", "Clear Search", "clearSearch"
		decision.disabled = false
	end
	self:decision("lead", decision)
	local measuring = self.model.scan.running == true
	if measuring and #rows == 0 then refs.files:showLoading() else refs.files:hideLoading() end
	-- An empty list says why it is empty: nothing matches the search, or
	-- this filter has no files.
	local query = state and state.query or ""
	local measured = self.model.files ~= nil
	local unavailable = fileState == "error" or fileState == "unavailable"
	refs.filesPanel.hidden = not measuring and (#rows == 0 or unavailable)
	refs.fileControls.hidden = unavailable or noLargeFiles or (measuring and #rows == 0)
	refs.filesUnavailable.hidden = not unavailable
	refs.filesNone.hidden = not (fileState == "empty" or (fileState == "loaded" and noLargeFiles))
	refs.filesEmpty.hidden = not (measured and #rows == 0 and query == "" and fileState == "loaded" and not noLargeFiles)
	refs.filesNoResults.hidden = not (measured and #rows == 0 and query ~= "" and fileState == "loaded" and not noLargeFiles)
	local summary = Files.summary(self.model)
	local kind = self.kind and Files.kindById(self.kind)
	refs.clearKind.hidden = kind == nil

	if not summary then
		for _, tile in ipairs(LAYOUT.tiles) do
			refs[tile.id .. "Value"].text = "—"
			refs[tile.id .. "Detail"].text = tile.detail
		end
		refs.summary.text = not measuring and "No file results are available. Refresh to try again."
			or "Measuring files… Results appear as they are found."
		return
	end
	refs.summary.text = (self.model.files.measuring and "Scan in progress · Found so far · " or "") .. "Files over " .. THRESHOLD .. " · " .. (summary.partial and "scan coverage is incomplete" or "largest first")
	refs.largeTileValue.text = Model.size(summary.bytes)
	refs.largeTileDetail.text = Model.plural(Model.count(summary.count), "file") .. ", largest first"
	refs.oldTileValue.text = Model.size(summary.oldBytes)
	refs.oldTileDetail.text = Model.plural(Model.count(summary.oldCount), "file") .. " not opened or changed in a year"
	refs.movableTileValue.text = Model.size(summary.reviewableOldBytes)
	refs.movableTileDetail.text = Model.plural(Model.count(summary.reviewableOld), "unused document") .. " you can move to the Trash"
end

-- Mark only the visible, user-owned subset. This stages the files; the
-- existing basket supplies the review and confirmation before removal.
function Controller:markFiles()
	local items = {}
	for _, row in ipairs(self.visible or {}) do
		if Files.validateTrash(self.model, row.path) and not self.actions:isIncluded(row.path) then
			table.insert(items, {path = row.path, name = row.name, bytes = row.bytes,
				source = "Large Files", consequence = "Moved to the Trash after your final review. Check that this is not your only copy."})
		end
	end
	return self.actions:markAll(items)
end

function Controller:marksChanged() self:update(self.state) end

return Controller
