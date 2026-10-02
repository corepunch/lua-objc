local Page = require("apps.diskmap.controllers.PageController")
local Model = require("apps.diskmap.Model")
local Duplicates = require("apps.diskmap.models.Duplicates")
local Controller = Page.extend("duplicates")

local LAYOUT = {
	summary = "Identical files in folders you choose.", summaryId = "duplicatesSummary",
	buttons = {{id = "addFolder", title = "Add Folder…", systemImage = "plus", action = "addFolder"},
		{id = "search", title = "Find Duplicates", action = "search", disabled = true}},
	sections = {{title = "Identical files", detailId = "duplicateRoots",
		empties = {
			{id = "dupChoose", title = "Choose Folders to Scan", systemImage = "folder.badge.plus",
				description = "Add a folder such as Downloads or Documents. Files are compared byte for byte; nothing is read outside the folders you add."},
			{id = "dupReady", hidden = true, title = "Ready to Search", systemImage = "doc.on.doc",
				description = "Choose Find Duplicates to compare the files in the folders above. Nothing has been read yet."},
			{id = "dupSearching", hidden = true, title = "Comparing Files", systemImage = "magnifyingglass",
				description = "Identical files appear here when the comparison finishes. Stop it at any time."},
			{id = "dupNone", hidden = true, title = "No Duplicates Found", systemImage = "checkmark.circle",
				description = "The search finished: no two files in the chosen folders are identical. Files under 1 MB are not compared."},
			{id = "dupNoMatch", hidden = true, title = "No Match", systemImage = "magnifyingglass",
				description = "No group of duplicates matches the search. Clear the search to see them all."},
			{id = "dupFailed", hidden = true, title = "The Search Did Not Finish", systemImage = "exclamationmark.triangle",
				description = "Diskmap could not read these folders. Check that it may access them, then choose Find Duplicates again."},
		},
		panelId = "duplicatesList",
		list = {id = "duplicates", menu = "menu", activate = "reveal", detailColumn = true}}},
	footnote = {text = "Copies that are APFS clones share their storage with the original: removing one frees only what it does not share, which is what Can free shows."},
}

-- The Duplicates page. Reading contents is a privacy boundary, so nothing
-- is read until the person adds a folder and starts a search, and only
-- that folder is read. Results last for the session.
function Controller.new(context)
	local service = context.service
	local load = rawget(service, "loadFolders")
	return setmetatable({model = context.model, service = service, actions = context.actions,
		roots = load and load("duplicates") or {}}, Controller)
end

function Controller:rootsText()
	if #self.roots == 0 then return "Add the folders to compare. Diskmap reads file contents only in them." end
	local names = {}
	for _, root in ipairs(self.roots) do table.insert(names, Model.tilde(root, self.model.home)) end
	return "Comparing files in " .. table.concat(names, ", ") .. "."
end

function Controller:mount(host, state)
	self.query = state.query or ""
	local refs = self:attach(host, {layout = LAYOUT, actions = {
		addFolder = function() self:addFolder() end,
		search = function() if self.job then self:stop() else self:search() end end,
		menu = function(_, _, row) return self:menu(row) end,
		reveal = function(_, _, row) if row then self.service.reveal(row.path) end end,
	}})
	self:show()
	return refs
end

function Controller:addFolder()
	local pick = rawget(self.service, "pickFolder")
	local path = pick and pick("Choose a Folder to Compare")
	if not path then return end
	for _, root in ipairs(self.roots) do if root == path then return end end
	table.insert(self.roots, path)
	local save = rawget(self.service, "saveFolders")
	if save then save("duplicates", self.roots) end
	self.result = nil
	self:show()
end

function Controller:search()
	if #self.roots == 0 then return end
	self.result, self.progress = nil, {examined = 0}
	self.job = self.service.findDuplicates(self.roots, function(result)
		self.job, self.result, self.progress = nil, result, nil
		self:show()
	end, function(progress) self.progress = progress; self:show() end)
	self:show()
end

function Controller:stop()
	if self.job then self.job.cancel() end
	self.job, self.progress = nil, nil
	self:show()
end

function Controller:menu(row)
	local items, keep = Duplicates.copies(row.group)
	local available, enclosing = {}, nil
	for _, item in ipairs(items) do
		local parent = self.actions:covering(item.path)
		if parent then enclosing = enclosing or parent.path else table.insert(available, item) end
	end
	local menu = {{title = #available > 0 and ("Mark " .. #available .. (#available == 1 and " Copy" or " Copies") .. " for Cleanup") or "Review Marked Items…",
		systemImage = #available > 0 and "plus.circle" or "checkmark.circle",
		action = function() if #available > 0 then self.actions:markAll(available) else self.actions.handlers.review(enclosing) end end}}
	table.insert(menu, {title = "Show Kept Copy", systemImage = "folder", action = function() self.service.reveal(keep.path) end})
	for _, item in ipairs(items) do
		table.insert(menu, {title = "Show " .. Model.tilde(item.path, self.model.home), systemImage = "doc",
			action = function() self.service.reveal(item.path) end})
	end
	return menu
end

function Controller:show()
	if not self.refs then return end
	local refs = self.refs
	refs.addFolder.enabled = not self.job
	refs.search.title = self.job and "Stop" or "Find Duplicates"
	refs.search.enabled = #self.roots > 0
	refs.duplicateRoots.text = self:rootsText()
	local groups = self.result and self.result.groups or {}
	if self.result and self.result.failure then groups = {} end
	local rows = self.actions:annotate(Duplicates.rows(groups, self.query, self.model.home))
	refs.duplicates:replaceRows(rows)
	local summary = Duplicates.summary(groups)
	local state = Duplicates.state(self.roots, self.job ~= nil, self.result, #rows, self.query)
	refs.duplicatesList.hidden = state ~= "list"
	for id, name in pairs({dupChoose = "choose", dupReady = "ready", dupSearching = "searching", dupNone = "none", dupNoMatch = "nomatch", dupFailed = "failed"}) do
		refs[id].hidden = state ~= name
	end
	refs.duplicatesSummary.text = self.job and string.format("Comparing… %s files examined", Model.count(self.progress and self.progress.examined or 0))
		or self.result and (self.result.failure or self.result.groups == nil) and "The search did not finish."
		or not self.result and (#self.roots == 0 and "Identical files in folders you choose." or "Ready to compare the chosen folders.")
		or summary.groups == 0 and "No identical files found."
		or string.format("%d %s could free %s", summary.copies, summary.copies == 1 and "copy" or "copies", Model.size(summary.bytes))
end

function Controller:update(state)
	if self.query == (state.query or "") then return end
	self.query = state.query or ""
	self:show()
end

function Controller:marksChanged() self:show() end

return Controller
