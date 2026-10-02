local Model = require("apps.diskmap.Model")
local Duplicates = require("apps.diskmap.models.Duplicates")

-- The Duplicates page. Reading contents is a privacy boundary, so nothing is
-- read until the person adds a folder and starts a search, and only that
-- folder is read. Results last for the session. While a search runs the page
-- is computing; otherwise exactly one of these notes shows, by
-- `Duplicates.state`, so "nothing chosen yet" is never read as "nothing found".
local EMPTIES = {
	{state = "choose", id = "dupChoose", title = "Choose Folders to Scan", systemImage = "folder.badge.plus",
		description = "Add a folder such as Downloads or Documents. Files are compared byte for byte; nothing is read outside the folders you add."},
	{state = "ready", id = "dupReady", title = "Ready to Search", systemImage = "doc.on.doc",
		description = "Choose Find Duplicates to compare the files in the folders above. Nothing has been read yet."},
	{state = "none", id = "dupNone", title = "No Duplicates Found", systemImage = "checkmark.circle",
		description = "The search finished: no two files in the chosen folders are identical. Files under 1 MB are not compared."},
	{state = "nomatch", id = "dupNoMatch", title = "No Match", systemImage = "magnifyingglass",
		description = "No group of duplicates matches the search. Clear the search to see them all."},
	{state = "failed", id = "dupFailed", title = "The Search Did Not Finish", systemImage = "exclamationmark.triangle",
		description = "Diskmap could not read these folders. Check that it may access them, then choose Find Duplicates again."},
}

local LAYOUT = {
	summary = "Identical files in folders you choose.",
	buttons = {{id = "addFolder", title = "Add Folder…", systemImage = "plus", action = "addFolder"},
		{id = "search", title = "Find Duplicates", action = "search"}},
	sections = {{title = "Identical files", detailId = "duplicateRoots", empties = EMPTIES, panelId = "duplicatesList",
		list = {id = "duplicates", menu = "rowMenu", activate = "reveal", detailColumn = true}}},
	footnote = {text = "Copies that are APFS clones share their storage with the original: removing one frees only what it does not share, which is what Can free shows."},
}

local function service(page) return page.services.service end

local function search(page)
	if #page.roots == 0 then return end
	page.result, page.progress = nil, {examined = 0}
	page.job = service(page).findDuplicates(page.roots, function(result)
		page.job, page.result, page.progress = nil, result, nil
		page.services.refresh()
	end, function(progress) page.progress = progress; page.services.refresh() end)
end

local function addFolder(page)
	local pick = rawget(service(page), "pickFolder")
	local path = pick and pick("Choose a Folder to Compare")
	if not path then return end
	for _, root in ipairs(page.roots) do if root == path then return end end
	table.insert(page.roots, path)
	local save = rawget(service(page), "saveFolders")
	if save then save("duplicates", page.roots) end
	page.result = nil
end

-- What a row offers: mark every copy but the kept one, or review the marks
-- when a marked folder already covers them; reveal each file.
local function menu(page, row)
	local items, keep = Duplicates.copies(row.group)
	local available, enclosing = {}, nil
	for _, item in ipairs(items) do
		local parent = page.actions:covering(item.path)
		if parent then enclosing = enclosing or parent.path else table.insert(available, item) end
	end
	local marking = #available > 0
	local reveal = service(page).reveal
	local menu = {{title = marking and ("Mark " .. #available .. (#available == 1 and " Copy" or " Copies") .. " for Cleanup") or "Review Marked Items…",
		systemImage = marking and "plus.circle" or "checkmark.circle",
		action = function() if marking then page.actions:markAll(available) else page.actions.handlers.review(enclosing) end end}}
	table.insert(menu, {title = "Show Kept Copy", systemImage = "folder", action = function() reveal(keep.path) end})
	for _, item in ipairs(items) do
		table.insert(menu, {title = "Show " .. Model.tilde(item.path, page.storage.home), systemImage = "doc", action = function() reveal(item.path) end})
	end
	return menu
end

local function summaryText(page, groups)
	local result = page.result
	if result and (result.failure or result.groups == nil) then return "The search did not finish." end
	if not result then return #page.roots == 0 and LAYOUT.summary or "Ready to compare the chosen folders." end
	local summary = Duplicates.summary(groups)
	if summary.groups == 0 then return "No identical files found." end
	return string.format("%d %s could free %s", summary.copies, summary.copies == 1 and "copy" or "copies", Model.size(summary.bytes))
end

return require("apps.diskmap.models.ListPage").class(function()
	return {id = "duplicates", layout = LAYOUT, actions = {
		addFolder = addFolder,
		search = function(page) if page.job then page.job.cancel(); page.job, page.progress = nil, nil else search(page) end end,
	}, menu = menu, present = function(storage, state, page)
		if not page.roots then
			local load = rawget(service(page), "loadFolders")
			page.roots = load and load("duplicates") or {}
		end
		local presented = {texts = {search = page.job and "Stop" or "Find Duplicates"}, disabled = {addFolder = page.job ~= nil, search = #page.roots == 0}}
		if page.job then
			presented.computing = string.format("Comparing… %s files examined", Model.count(page.progress and page.progress.examined or 0))
			return presented
		end
		local result = page.result
		local groups = result and not result.failure and result.groups or {}
		local rows = page.actions:annotate(Duplicates.rows(groups, state.query, storage.home))
		local current = Duplicates.state(page.roots, result, #rows, state.query)
		local names = {}
		for _, root in ipairs(page.roots) do table.insert(names, Model.tilde(root, storage.home)) end
		local hidden = {duplicatesList = current ~= "list"}
		for _, empty in ipairs(EMPTIES) do hidden[empty.id] = current ~= empty.state end
		presented.lists, presented.hidden = {duplicates = rows}, hidden
		presented.texts.summary = summaryText(page, groups)
		presented.texts.duplicateRoots = #names == 0 and "Add the folders to compare. Diskmap reads file contents only in them."
			or "Comparing files in " .. table.concat(names, ", ") .. "."
		return presented
	end}
end)
