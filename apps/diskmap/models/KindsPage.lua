local Model = require("apps.diskmap.Model")
local DataModel = require("data.model")
local Files = require("apps.diskmap.models.Files")
local Inventory = require("apps.diskmap.models.Inventory")
local Selection = require("apps.diskmap.models.Selection")
local Scope = require("apps.diskmap.models.Scope")
local Sectors = require("ui.sectors")

-- File Types: extension totals grouped into kinds, with a donut, advice for
-- the largest kind and the top extensions. The selected kind is the page's
-- selection token: its sector, its row, the headline and the top extensions
-- all name it.
local WAITING = {title = "File Types Not Measured Yet", systemImage = "square.grid.2x2", description = "File types are listed when the scan finishes."}
local Kinds = DataModel.define({id = "kinds"})
-- Hovering, menus and the lead card's buttons only read or navigate.
Kinds.queries = {selectKind = true, chartHover = true, kindMenu = true, openKind = true, showHeadline = true, showInstallers = true, showOld = true,
	cleanup = true, refresh = true, clearSearch = true}

function Kinds.new(_, services) return setmetatable({storage = services.model, services = services}, Kinds) end

-- Large Files, narrowed to one kind.
function Kinds:showFiles(kind) self.services.showFiltered("files", Files.filterIndex("All"), kind) end
function Kinds:showInstallers() self.services.showFiltered("files", Files.filterIndex("Installers & archives")) end
function Kinds:showOld() self.services.showFiltered("files", Files.filterIndex("Unused for a year")) end
function Kinds:cleanup() self.services.show("cleanup") end
function Kinds:refresh() self.services.rescan() end
function Kinds:clearSearch() self.services.search("kinds", "") end
function Kinds:showHeadline() if self.headlineId then self:showFiles(self.headlineId) end end
function Kinds:openKind(_, _, row) if row then self:showFiles(row.kindId or row.id) end end

function Kinds:kindMenu(_, _, row)
	local kindId = row.kindId or row.id
	local kind = Files.kindById(kindId)
	return {{title = "Show Largest " .. (kind and kind.name or "Files"), systemImage = "doc.fill", action = function() self:showFiles(kindId) end}}
end

-- A row the pointer selected through its sector is only pointed at; one
-- the person selected is the kept kind, and the page is drawn again for it.
function Kinds:selectKind(_, _, row)
	if not row or self.pointing or row.id == self.selectedId then return end
	self.selectedId = row.id
	self.services.refresh()
end

-- A click keeps the kind; a click on the kind already kept opens its largest files.
function Kinds:chartSelect(id)
	if id == self.selectedId then self:showFiles(id) else self.selectedId = Selection.index(self.kinds, id) and id or nil end
end

-- The pointer over a sector points at its row; leaving the chart returns to
-- the kind that was kept.
function Kinds:chartHover(id)
	local refs = self.refs
	if not refs then return end
	self.pointing = true
	Selection.show(refs.kinds, self.kinds, id or self.selectedId)
	self.pointing = false
	if not id and refs.kindsChart then Sectors.highlight(refs.kindsChart, self.selectedId) end
end

-- The leading decision: the files of yours this page can point at, never a
-- kind's whole inventory. Disk images share an extension with system and
-- app images, so only the user-owned subset is offered.
function Kinds:decision(kinds)
	local data = {id = "decision", icon = "opticaldiscdrive.fill", color = "systemTeal"}
	if #kinds == 0 then
		local state, reason = Files.state(self.storage)
		data.amount, data.amountCaption = "—", "not measured"
		if state == "empty" then
			data.title, data.detail, data.amountCaption = "No files found in the measured locations", "Clean Up can still guide you through rebuildable data and owner-managed storage.", "scan finished"
			data.actionTitle, data.action = "Open Clean Up", "cleanup"
		else
			data.title, data.detail = "File type results unavailable", reason or "No extension totals were recorded. Refresh the scan to try again."
			data.actionTitle, data.action = "Refresh Scan", "refresh"
		end
		return data
	end
	local installers = Files.rows(self.storage, "Installers & archives")
	local removable = 0
	for _, row in ipairs(installers) do removable = removable + row.bytes end
	local files = Files.summary(self.storage)
	if removable > 0 then
		data.title = "Review " .. (#installers == 1 and "1 installer or archive" or (#installers .. " installers and archives")) .. " in your folders"
		data.detail = "Check that you have installed or extracted them before moving them to the Trash."
		data.amount, data.amountCaption = Model.size(removable), "could recover"
		data.actionTitle, data.action = "Show Installers", "showInstallers"
	elseif files and files.reviewableOld > 0 then
		data.icon, data.color = "clock.fill", "systemOrange"
		data.title = "Review " .. Model.plural(files.reviewableOld, "file") .. " of yours unused for a year"
		data.detail = "No installer or archive in your folders is large enough to list. These files were not opened or changed in a year; they may be your only copy."
		data.amount, data.amountCaption = Model.size(files.reviewableOldBytes), "to review"
		data.actionTitle, data.action = "Show Unused Files", "showOld"
	else
		data.icon, data.color = "checkmark.circle.fill", "systemGreen"
		data.title = "No large file of yours to review"
		data.detail = "No user-owned file over " .. Model.size(Inventory.summary.minimumFileBytes) .. " was ranked. Clean Up lists other places their owners can clear."
		data.amount, data.amountCaption = Model.size(0), "could recover"
		data.actionTitle, data.action = "Open Clean Up", "cleanup"
	end
	return data
end

-- The kinds and extensions the search leaves.
local function search(kinds, extensions, query)
	local matches, matchedKinds = {}, {}
	for _, extension in ipairs(extensions) do
		if (extension.name .. " " .. extension.subtitle):lower():find(query, 1, true) then
			table.insert(matches, extension); matchedKinds[extension.kindId] = true
		end
	end
	local found = {}
	for _, kind in ipairs(kinds) do
		if kind.name:lower():find(query, 1, true) or matchedKinds[kind.id] then table.insert(found, kind) end
	end
	return found, matches
end

function Kinds:data(state)
	local model = self.storage
	local fileState = Files.state(model)
	self.kinds, self.headlineId = {}, nil
	-- Nothing is listed until the scan has measured the files.
	if fileState == "loading" then return {waiting = WAITING, summary = ""} end
	local kinds, extensions = Files.kinds(model)
	if fileState == "error" or fileState == "unavailable" then kinds, extensions = {}, {} end
	local query = (state.query or ""):lower()
	if query ~= "" then kinds, extensions = search(kinds, extensions, query) end
	self.kinds = kinds
	if not Selection.index(kinds, self.selectedId) then self.selectedId = nil end
	local all, marks, labels = 0, {}, {}
	for _, kind in ipairs(kinds) do
		all = all + kind.bytes
		kind.detail = Model.count(kind.count)
		table.insert(marks, {id = kind.id, name = kind.name, color = kind.color, bytes = kind.bytes})
		table.insert(labels, kind.name .. " " .. kind.size)
	end
	for _, row in ipairs(extensions) do row.detail = Model.count(row.count) end
	-- The headline names the selected kind, or else the largest kind a
	-- person can act on; "Other files" and databases belong to apps.
	local headline, selected
	for _, kind in ipairs(kinds) do
		if kind.id == self.selectedId then headline, selected = kind, kind; break end
	end
	for _, kind in ipairs(kinds) do
		if not headline and kind.id ~= "other" and kind.id ~= "databases" then headline = kind end
	end
	headline = headline or kinds[1]
	self.headlineId = headline and headline.id
	local inventoryNote = "All measured files, including app and system storage; only files in your own folders are offered for review above."
	if headline and headline.removableBytes then
		inventoryNote = headline.size .. " total stored; " .. Model.size(headline.removableBytes) .. " in your own folders. The rest belongs to apps or the system."
	end
	local decision = self:decision(kinds)
	local summary = Model.size(all) .. " in files across " .. #kinds .. " kinds"
	if #kinds == 0 then
		if fileState == "empty" then summary = "Scan complete · No files found"
		elseif fileState == "loaded" and query ~= "" then
			summary = "No matching file types"
			decision.title, decision.detail = "Nothing matches this search", "Clear the search to see the measured file types."
			decision.amountCaption, decision.actionTitle, decision.action = "no matches", "Clear Search", "clearSearch"
		else summary = "File type results unavailable" end
	elseif model.files and model.files.partial then summary = summary .. " · scan coverage is incomplete" end
	local lists = {extensions = #extensions > 0 and Selection.extensions(extensions, self.selectedId) or nil}
	if #kinds > 0 then lists.kinds = kinds end
	return {kinds = marks, total = Model.size(all), scope = Scope.text(model, "kinds"), summary = summary, hasExtensions = #extensions > 0,
		accessibilityLabel = "File types: " .. table.concat(labels, ", "), decision = decision, inventoryNote = inventoryNote,
		headline = headline and {title = headline.name .. " · " .. headline.size .. " stored"} or {},
		extensionsDetail = selected and ("The " .. selected.name .. " extensions that use the most space") or "The twelve extensions that use the most space",
		lists = lists}
end

-- After a draw the native selection and the chart follow the token.
function Kinds:rendered(refs)
	self.refs = refs
	Selection.show(refs.kinds, self.kinds, self.selectedId)
	if refs.kindsChart then Sectors.highlight(refs.kindsChart, self.selectedId) end
end

function Kinds:deactivate() self.refs = nil end

return Kinds
