local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Files = require("apps.diskmap.models.Files")
local Selection = require("apps.diskmap.models.Selection")
local Scope = require("apps.diskmap.models.Scope")
local Sectors = require("ui.sectors")
local Controller = Page.extend("kinds", "Kinds")

-- File Types: extension totals grouped into kinds, with a donut, advice for
-- the largest kind and the top extensions. `showFiles(kindId)` opens Large
-- Files narrowed to one kind; `show(page, filterName)` opens a page, Large
-- Files on one of its filters.
function Controller.new(context)
	return setmetatable({model = context.model,
		showFiles = function(kind) context.pageModel("files"):focus(kind); context.show("files", true) end,
		show = function(id, filter) context.showFiltered(id, filter and Files.filterIndex(filter)) end,
		refresh = context.rescan, clearSearch = function() context.search("kinds", "") end}, Controller)
end

-- The leading decision: the files of yours this page can point at, never a
-- kind's whole inventory. Disk images share an extension with system and
-- app images, so only the user-owned subset is offered.
function Controller:decisionData(kinds)
	local data = {id = "decision", icon = "opticaldiscdrive.fill", color = "systemTeal"}
	if #kinds == 0 then
		local state, reason = Files.state(self.model)
		data.amount, data.amountCaption = "—", "not measured"
		if state == "loading" then
			data.title, data.detail, data.amountCaption = "Measuring file types…", "Results appear as the scan reads files.", "in progress"
		elseif state == "empty" then
			data.title, data.detail, data.amountCaption = "No files found in the measured locations", "Clean Up can still guide you through rebuildable data and owner-managed storage.", "scan finished"
			data.actionTitle, data.action = "Open Clean Up", "decisionCleanup"
		else
			data.title, data.detail = "File type results unavailable", reason or "No extension totals were recorded. Refresh the scan to try again."
			data.actionTitle, data.action = "Refresh Scan", "decisionRefresh"
		end
		return data
	end
	local installers = Files.rows(self.model, "Installers & archives")
	local removable = 0
	for _, row in ipairs(installers) do removable = removable + row.bytes end
	if removable > 0 then
		data.title = "Review " .. (#installers == 1 and "1 installer or archive" or (#installers .. " installers and archives")) .. " in your folders"
		data.detail = "Check that you have installed or extracted them before moving them to the Trash."
		data.amount, data.amountCaption = Model.size(removable), "could recover"
		data.actionTitle, data.action = "Show Installers", "decisionInstallers"
		return data
	end
	local files = Files.summary(self.model)
	if files and files.reviewableOld > 0 then
		data.icon, data.color = "clock.fill", "systemOrange"
		data.title = "Review " .. Model.plural(files.reviewableOld, "file") .. " of yours unused for a year"
		data.detail = "No installer or archive in your folders is large enough to list. These files were not opened or changed in a year; they may be your only copy."
		data.amount, data.amountCaption = Model.size(files.reviewableOldBytes), "to review"
		data.actionTitle, data.action = "Show Unused Files", "decisionOld"
		return data
	end
	data.icon, data.color = "checkmark.circle.fill", "systemGreen"
	data.title = "No large file of yours to review"
	data.detail = "No user-owned file over " .. Model.size(require("apps.diskmap.models.Inventory").summary.minimumFileBytes) .. " was ranked. Clean Up lists other places their owners can clear."
	data.amount, data.amountCaption = Model.size(0), "could recover"
	data.actionTitle, data.action = "Open Clean Up", "decisionCleanup"
	return data
end

function Controller:mount(host, state)
	self:attach(host)
	self:update(state)
	return self.refs
end

function Controller:menu(row)
	local kindId = row.kindId or row.id
	local kind = Files.kindById(kindId)
	return {{title = "Show Largest " .. (kind and kind.name or "Files"), systemImage = "doc.fill", action = function() self.showFiles(kindId) end}}
end

-- The chart and headline re-render only when the set of kinds or the
-- selected kind changes; list rows update in place. The selected kind is the
-- page's selection token: its sector, its row, the headline and the top
-- extensions all name it.
function Controller:update(state)
	if not self.template then return end
	self.state = state or self.state or {}
	local kinds, extensions = Files.kinds(self.model)
	local fileState, reason = Files.state(self.model)
	if fileState == "error" or fileState == "unavailable" then kinds, extensions = {}, {} end
	local query = (self.state.query or ""):lower()
	if query ~= "" then
		local matches, matchedKinds = {}, {}
		for _, extension in ipairs(extensions) do
			if (extension.name .. " " .. extension.subtitle):lower():find(query, 1, true) then
				table.insert(matches, extension); matchedKinds[extension.kindId] = true
			end
		end
		extensions = matches
		matches = {}
		for _, kind in ipairs(kinds) do
			if kind.name:lower():find(query, 1, true) or matchedKinds[kind.id] then table.insert(matches, kind) end
		end
		kinds = matches
	end
	if not Selection.index(kinds, self.selectedId) then self.selectedId = nil end
	local all = 0
	for _, kind in ipairs(kinds) do all = all + kind.bytes end
	local marks, labels = {}, {}
	for _, kind in ipairs(kinds) do
		table.insert(marks, {id = kind.id, name = kind.name, color = kind.color, bytes = kind.bytes})
		table.insert(labels, kind.name .. " " .. kind.size)
	end
	-- The headline names the selected kind, or else the largest kind a
	-- person can act on; "Other files" and databases belong to apps.
	local headline
	for _, kind in ipairs(kinds) do
		if kind.id == self.selectedId then headline = kind; break end
	end
	if not headline then
		for _, kind in ipairs(kinds) do
			if kind.id ~= "other" and kind.id ~= "databases" then headline = kind; break end
		end
	end
	headline = headline or kinds[1]
	local inventoryNote = "All measured files, including app and system storage; only files in your own folders are offered for review above."
	if headline and headline.removableBytes then
		inventoryNote = headline.size .. " total stored; " .. Model.size(headline.removableBytes) .. " in your own folders. The rest belongs to apps or the system."
	end
	local actions = {
		kindMenu = function(_, _, row) return self:menu(row) end,
		openKind = function(_, _, row) if row then self.showFiles(row.kindId or row.id) end end,
		-- A row the pointer selected through its sector is only pointed at.
		selectKind = function(_, _, row) if row and not self.pointing then self:select(row.id) end end,
		-- The pointer over a sector points at its row; a click keeps the
		-- kind, and a click on the kind already kept opens its largest files.
		-- Leaving the chart returns to the kind that was kept.
		chartHover = function(id)
			if not self.refs then return end
			self.pointing = true
			Selection.show(self.refs.kinds, self.kinds, id or self.selectedId)
			self.pointing = false
			if not id and self.refs.kindsChart then Sectors.highlight(self.refs.kindsChart, self.selectedId) end
		end,
		chartSelect = function(id)
			if id == self.selectedId then self.showFiles(id) else self:select(id) end
		end,
	}
	for _, kind in ipairs(kinds) do actions["kind_" .. kind.id] = function() self.showFiles(kind.id) end end
	local selected = self.selectedId and headline or nil
	actions.decisionInstallers = function() if self.show then self.show("files", "Installers & archives") end end
	actions.decisionOld = function() if self.show then self.show("files", "Unused for a year") end end
	actions.decisionCleanup = function() if self.show then self.show("cleanup") end end
	actions.decisionRefresh = function() self.refresh() end
	actions.decisionClearSearch = function() self.clearSearch() end
	local decision = self:decisionData(kinds)
	local summary = Model.size(all) .. " in files across " .. #kinds .. " kinds"
	if #kinds == 0 then
		if fileState == "loading" then summary = "Scan in progress"
		elseif fileState == "empty" then summary = "Scan complete · No files found"
		elseif fileState == "loaded" and query ~= "" then
			summary = "No matching file types"
			decision.title, decision.detail = "Nothing matches this search", "Clear the search to see the measured file types."
			decision.amountCaption, decision.actionTitle, decision.action = "no matches", "Clear Search", "decisionClearSearch"
		else summary = "File type results unavailable" end
	elseif fileState == "loading" then summary = "Scan in progress · " .. summary
	elseif self.model.files and self.model.files.partial then summary = summary .. " · scan coverage is incomplete" end
	local refs = self:render({kinds = marks, total = Model.size(all), scope = Scope.text(self.model, "kinds"),
		summary = summary, loading = fileState == "loading", hasExtensions = #extensions > 0,
		accessibilityLabel = "File types: " .. table.concat(labels, ", "),
		headline = headline and {id = headline.id, title = headline.name .. " · " .. headline.size .. " stored", advice = headline.advice} or {}, inventoryNote = inventoryNote,
		decision = decision,
		extensionsDetail = selected and ("The " .. selected.name .. " extensions that use the most space")
			or "The twelve extensions that use the most space",
		actions = actions})
	self.kinds = kinds
	for _, kind in ipairs(kinds) do kind.detail = Model.count(kind.count) end
	if refs.kinds then
		refs.kinds:replaceRows(kinds)
		if fileState == "loading" and #kinds == 0 then refs.kinds:showLoading() else refs.kinds:hideLoading() end
	end
	for _, row in ipairs(extensions) do row.detail = Model.count(row.count) end
	if refs.extensions then refs.extensions:replaceRows(Selection.extensions(extensions, self.selectedId)) end
	-- Reloading rows drops the native selection; the token restores it.
	Selection.show(refs.kinds, kinds, self.selectedId)
	if refs.kindsChart then Sectors.highlight(refs.kindsChart, self.selectedId) end
end

-- Keeps `id` as the selected kind: the headline and the top extensions
-- follow it, and its sector stays highlighted.
function Controller:select(id)
	id = Selection.index(self.kinds, id) and id or nil
	if self.selectedId == id then return end
	self.selectedId = id
	self:update()
end

return Controller
