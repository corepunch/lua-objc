local Model = require("data.model")
local Files = require("apps.diskmap.models.Files")
local Format = require("apps.diskmap.helpers.Format")
local Inventory = require("apps.diskmap.helpers.Inventory")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Scope = require("apps.diskmap.helpers.Scope")

local routes = {}

local THRESHOLD = Format.size(Inventory.summary.minimumFileBytes)
local LAYOUT = {
	summary = "Measuring files…", scopeNote = Scope.pages.files, leads = {"lead"}, contextAfterSections = true, contextDisclosure = "Scan scope and statistics",
	tiles = {
		{id = "largeTile", icon = "doc.fill", color = "systemTeal", title = "Over " .. THRESHOLD, value = "—", detail = "Individual files, largest first"},
		{id = "oldTile", icon = "clock.fill", color = "systemOrange", title = "Unused for a year", value = "—", detail = "Not opened or changed since"},
		{id = "movableTile", icon = "trash.fill", color = "systemRed", title = "Yours to review", value = "—", detail = "Unused documents you can move to the Trash"},
	},
	sections = {{
		controlsId = "fileControls",
		links = {{id = "clearKind", title = "Show All Kinds", style = "link", action = "clearKind"}},
		filters = {id = "filter", options = Files.filters},
		empties = {
			{id = "filesUnavailable", title = "File Results Unavailable", systemImage = "exclamationmark.triangle", description = "Check scan access, then refresh to measure files again."},
			{id = "filesNone", title = "No Large Files Found", systemImage = "doc", description = "No files over " .. THRESHOLD .. " were ranked. Clean Up can still find rebuildable data."},
			{id = "filesNoResults", title = "No Results", systemImage = "magnifyingglass", description = "No large file matches the search. Try another filter or search."},
			{id = "filesEmpty", title = "No Files Here", systemImage = "doc", description = "No large file fits this filter. Choose All to see every file Diskmap ranked."},
		},
		panelId = "filesPanel",
		list = {id = "files", menu = "rowMenu", activate = "reveal", detailColumn = true, fileIcons = true}}},
	footnote = {text = "Diskmap reads only names, sizes and dates. Files inside apps, libraries and hidden tool folders are listed for context and managed by their owners; only your own documents can be moved to the Trash here."},
}

local WAITING = {title = "Files Not Measured Yet", systemImage = "doc", description = "Large files are listed when the scan finishes."}
local LINKS = {cleanup = {page = "cleanup"}, reviewMarked = {handler = "review"}, refreshFiles = {handler = "refresh"},
	clearSearch = {handler = "search", args = {"files", ""}}}

-- The lead card: what a person can mark here, or why there is nothing to.
local function decision(page, rows, fileState, reason, query, kind, noFiles)
	local filter, actions = Files.filters[page.filterIndex], page.rowActions
	local bytes, reviewable, marked, included = 0, 0, 0, 0
	for _, row in ipairs(rows) do
		bytes = bytes + row.bytes
		if Files:validateTrash(row.path) then
			if actions:isMarked(row.path) then marked = marked + 1
			elseif actions:isIncluded(row.path) then marked, included = marked + 1, included + 1
			else reviewable = reviewable + 1 end
		end
	end
	local data = {id = "decision", icon = "doc.fill", color = "systemTeal",
		title = (kind and kind.name or filter) .. " · " .. Format.plural(#rows, "file"),
		detail = filter == "Installers & archives" and "Check that these are installed or extracted. Marking stages them for your final review."
			or "Review the contents before marking. Files inside apps or libraries stay with their owners.",
		amount = Format.size(bytes), amountCaption = "to review",
		actionTitle = reviewable > 0 and ("Mark " .. Format.plural(reviewable, "File")) or (marked > 0 and "Review Marked Items…" or "No Files to Mark"),
		action = reviewable > 0 and "markFiles" or "reviewMarked", disabled = reviewable == 0 and marked == 0,
		secondaryTitle = reviewable > 0 and marked > 0 and "Review Marked Items…" or nil, secondaryAction = "reviewMarked"}
	if included > 0 then data.detail = Format.plural(included, "file") .. " included through a marked folder. Review the folder to change its cleanup plan." end
	local function say(title, detail, caption, actionTitle, action)
		data.title, data.detail, data.amount, data.amountCaption = title, detail, "—", caption
		data.actionTitle, data.action, data.disabled = actionTitle, action, false
	end
	if noFiles then
		say("No large files found", "No files over " .. THRESHOLD .. " were ranked. Review rebuildable data in Clean Up.", "scan finished", "Open Clean Up", "cleanup")
	elseif fileState == "error" or fileState == "unavailable" then
		say("File results unavailable", reason, "not measured", "Refresh Scan", "refreshFiles")
	elseif #rows == 0 and query ~= "" then
		say("Nothing matches this search", "Clear the search or choose another filter to review the measured files.", "no matches", "Clear Search", "clearSearch")
	end
	return data
end

-- Large Files: the individual files the last scan ranked, with filters for
-- files unused for a year, installers and media. File Types opens it on one
-- kind (`focus`).
routes.files = ListRoute.extend({layout = LAYOUT, children = {lead = "sections/Decision"}, menu = function(page, row) return page.rowActions:file(row) end,
	-- Opens the page narrowed to one File Types kind and one filter.
	focus = function(page, kind, filterIndex) page.kind, page.filterIndex = kind, filterIndex or 1 end,
	clearKind = function(page) page.kind = nil end,
	-- Mark only the visible, user-owned subset. This stages the files; the
	-- existing basket supplies the review and confirmation before removal.
	markFiles = function(page)
		local items = {}
		for _, row in ipairs(page.visible or {}) do
			if Files:validateTrash(row.path) and not page.rowActions:isIncluded(row.path) then
				table.insert(items, {path = row.path, name = row.name, bytes = row.bytes,
					source = "Large Files", consequence = "Moved to the Trash after your final review. Check that this is not your only copy."})
			end
		end
		return page.rowActions:markAll(items)
	end, present = function(page, state)
		local model = Model.db
		-- Nothing is listed until the scan has measured the files.
		local fileState, reason = Files:state()
		page.visible = {}
		if fileState == "loading" then return {waiting = WAITING} end
		local query, kind = state.query or "", page.kind and Files.kindById(page.kind)
		local files, summary = model.files, Files:summary()
		local rows = Files:rows(Files.filters[page.filterIndex], query, page.kind)
		page.visible = rows
		local noLarge = files ~= nil and #files.large == 0 and #files.old == 0
		local noFiles = fileState == "empty" or (fileState == "loaded" and noLarge)
		local unavailable = fileState == "error" or fileState == "unavailable"
		local listed = files ~= nil and #rows == 0 and fileState == "loaded" and not noLarge
		local texts = {scopeNote = Scope.text("files"), summary = not summary and "No file results are available. Refresh to try again."
			or "Files over " .. THRESHOLD .. " · " .. (summary.partial and "scan coverage is incomplete" or "largest first")}
		if summary then
			texts.largeTileValue, texts.largeTileDetail = Format.size(summary.bytes), Format.plural(Format.count(summary.count), "file") .. ", largest first"
			texts.oldTileValue, texts.oldTileDetail = Format.size(summary.oldBytes), Format.plural(Format.count(summary.oldCount), "file") .. " not opened or changed in a year"
			texts.movableTileValue = Format.size(summary.reviewableOldBytes)
			texts.movableTileDetail = Format.plural(Format.count(summary.reviewableOld), "unused document") .. " you can move to the Trash"
		end
		return {lists = {files = page.rowActions:annotate(rows)}, texts = texts, links = LINKS,
			children = {lead = decision(page, rows, fileState, reason, query, kind, noFiles)}, hidden = {
				filesPanel = #rows == 0 or unavailable, fileControls = unavailable or noLarge,
				filesUnavailable = not unavailable, filesNone = not noFiles,
				filesEmpty = not (listed and query == ""), filesNoResults = not (listed and query ~= ""), clearKind = kind == nil}}
	end})

return routes
