local Model = require("data.model")
local Core = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Inventory = require("apps.diskmap.models.Inventory")
local Scope = require("apps.diskmap.models.Scope")

-- Large Files: the individual files the last scan ranked, with filters for
-- files unused for a year, installers and media. A page model: it reads the
-- storage and the toolbar search, owns the filter, and answers for every
-- field of schemas/FilesPage.xml; views/Files.etlua binds to them. A schema
-- command is a method: `menu` builds a row's menu, `reveal` activates a row.
local FilesPage = Model.define({id = "files", schema = "FilesPage", needs = {"storage", "session"}})

local THRESHOLD = Core.size(Inventory.summary.minimumFileBytes)
-- What the view states and lists: the size threshold and the filter names.
FilesPage.threshold = THRESHOLD
FilesPage.filters = Files.filters

function FilesPage.new(needs, services)
	return setmetatable({storage = needs.storage, session = needs.session, service = services.service,
		actions = services.actions, filterIndex = 1}, FilesPage)
end

-- File Types opens this page narrowed to one kind.
function FilesPage:focus(kind)
	self.kind, self.filterIndex = kind, Files.filterIndex("All")
	self:changed()
end

-- The filter segmented control is zero based.
function FilesPage:setFilter(index)
	self.filterIndex = (index or 0) + 1
end

function FilesPage:clearKind()
	self.kind = nil
end

-- Mark only the visible, user-owned subset. This stages the files; the
-- existing basket supplies the review and confirmation before removal.
function FilesPage:markFiles()
	local items = {}
	for _, row in ipairs(self.visible or {}) do
		if Files.validateTrash(self.storage, row.path) and not self.actions:isIncluded(row.path) then
			table.insert(items, {path = row.path, name = row.name, bytes = row.bytes,
				source = "Large Files", consequence = "Moved to the Trash after your final review. Check that this is not your only copy."})
		end
	end
	return self.actions:markAll(items)
end

function FilesPage:menu(row) return self.actions:file(row) end

function FilesPage:reveal(row)
	if row then self.service.reveal(row.path) end
end

local function plural(count, word) return Core.plural(count, word) end

-- Works out everything the fields answer from, once per rebind.
function FilesPage:prepare()
	local storage, query = self.storage, self.session.query or ""
	local handlers = self.actions.handlers
	local filter = Files.filters[self.filterIndex]
	local fileState, stateReason = Files.state(storage)
	local files = storage.files
	local noLargeFiles = files ~= nil and #(files.large or {}) == 0 and #(files.old or {}) == 0 and fileState ~= "loading"
	local rows = Files.rows(storage, filter, query, self.kind)
	self.visible = rows
	self.rows = self.actions:annotate(rows)
	local bytes, reviewable, marked, included = 0, 0, 0, 0
	for _, row in ipairs(rows) do
		bytes = bytes + row.bytes
		if Files.validateTrash(storage, row.path) then
			if self.actions:isMarked(row.path) then marked = marked + 1
			elseif self.actions:isIncluded(row.path) then marked, included = marked + 1, included + 1
			else reviewable = reviewable + 1 end
		end
	end
	local kind = self.kind and Files.kindById(self.kind)
	local lead = {shown = true, icon = "doc.fill", color = "systemTeal",
		title = (kind and kind.name or filter) .. " · " .. plural(#rows, "file"),
		detail = filter == "Installers & archives" and "Check that these are installed or extracted. Marking stages them for your final review."
			or "Review the contents before marking. Files inside apps or libraries stay with their owners.",
		amount = Core.size(bytes), amountCaption = "to review",
		actionTitle = reviewable > 0 and ("Mark " .. plural(reviewable, "File")) or (marked > 0 and "Review Marked Items…" or "No Files to Mark"),
		runnable = not ((reviewable == 0 and marked == 0) or storage.scan.running),
		secondaryTitle = reviewable > 0 and marked > 0 and "Review Marked Items…" or nil,
		secondary = function() handlers.review() end}
	lead.run = reviewable > 0 and function() self:markFiles() end or function() handlers.review() end
	if included > 0 then lead.detail = plural(included, "file") .. " included through a marked folder. Review the folder to change its cleanup plan." end
	local function reroute(title, detail, caption, actionTitle, run)
		lead.title, lead.detail = title, detail
		lead.amount, lead.amountCaption, lead.actionTitle, lead.run = "—", caption, actionTitle, run
		lead.runnable = actionTitle ~= nil
	end
	if #rows == 0 and fileState == "loading" then
		reroute("Looking for large files…", "Results appear as they are measured. Marking is available after the scan finishes.", "in progress", nil)
	elseif fileState == "empty" or (fileState == "loaded" and noLargeFiles) then
		reroute("No large files found", "No files over " .. THRESHOLD .. " were ranked. Review rebuildable data in Clean Up.",
			"scan finished", "Open Clean Up", function() handlers.show("cleanup") end)
	elseif fileState == "error" or fileState == "unavailable" then
		reroute("File results unavailable", stateReason, "not measured", "Refresh Scan", function() handlers.refresh() end)
	elseif #rows == 0 and query ~= "" then
		reroute("Nothing matches this search", "Clear the search or choose another filter to review the measured files.",
			"no matches", "Clear Search", function() handlers.search("files", "") end)
	end
	self.lead = lead
	local measuring = storage.scan.running == true
	local unavailable = fileState == "error" or fileState == "unavailable"
	self.isLoading = measuring and #rows == 0
	self.showPanel = measuring or not (#rows == 0 or unavailable)
	self.showControls = not (unavailable or noLargeFiles or (measuring and #rows == 0))
	self.unavailable = unavailable
	self.none = fileState == "empty" or (fileState == "loaded" and noLargeFiles)
	local measured = files ~= nil
	self.emptyFilter = measured and #rows == 0 and query == "" and fileState == "loaded" and not noLargeFiles
	self.noResults = measured and #rows == 0 and query ~= "" and fileState == "loaded" and not noLargeFiles
	local summary = Files.summary(storage)
	if not summary then
		self.summaryText = not measuring and "No file results are available. Refresh to try again."
			or "Measuring files… Results appear as they are found."
		self.tiles = {large = {value = "—", detail = "Individual files, largest first"},
			old = {value = "—", detail = "Not opened or changed since"},
			movable = {value = "—", detail = "Unused documents you can move to the Trash"}}
		return
	end
	self.summaryText = (files.measuring and "Scan in progress · Found so far · " or "") .. "Files over " .. THRESHOLD .. " · "
		.. (summary.partial and "scan coverage is incomplete" or "largest first")
	self.tiles = {
		large = {value = Core.size(summary.bytes), detail = plural(Core.count(summary.count), "file") .. ", largest first"},
		old = {value = Core.size(summary.oldBytes), detail = plural(Core.count(summary.oldCount), "file") .. " not opened or changed in a year"},
		movable = {value = Core.size(summary.reviewableOldBytes), detail = plural(Core.count(summary.reviewableOld), "unused document") .. " you can move to the Trash"},
	}
end

-- Field accessors for schemas/FilesPage.xml.
function FilesPage:summary() return self.summaryText end
function FilesPage:scope() return {text = Scope.text(self.storage, "files")} end
function FilesPage:largeTile() return self.tiles.large end
function FilesPage:oldTile() return self.tiles.old end
function FilesPage:movableTile() return self.tiles.movable end
function FilesPage:filter() return self.filterIndex - 1 end
function FilesPage:kindFiltered() return self.kind ~= nil end
function FilesPage:loading() return self.isLoading end
function FilesPage:files() return self.rows end

return FilesPage
