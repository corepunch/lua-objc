local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local VolumeContents = require("apps.diskmap.models.VolumeContents")

-- One watched location, opened from its sidebar row ("watched:<key>", the
-- app's current destination): its size, the change since the previous session
-- and what it holds one level down. A category lists its locations; a folder
-- is measured when the page opens, unless the scan already broke it down.
local FOOTNOTE = {icon = "eye", text = "Diskmap stores each watched location's size after every scan and shows how it changed the next time you open it. Only the location and its size are kept, never file names inside it."}

local function service(page) return page.services.service end

local function key(page) return page.services.destination():match("^watched:(.+)$") end

local function watched(page)
	for _, row in ipairs(page.services.watchlist:rows()) do
		if row.key == key(page) then return row end
	end
end

-- The resource whose category sheet the page's Open button shows: a group
-- itself, or a leaf's parent.
local function category(page, row)
	local resource = row.resourceId and page.storage.resources:find(row.resourceId)
	if not resource then return nil end
	return resource:isLeaf() and resource:getParent() or resource
end

local function group(page, row)
	local resource = row.resourceId and page.storage.resources:find(row.resourceId)
	return resource and not resource:isLeaf() and resource or nil
end

-- A folder's immediate children: the scan's breakdown when it made one,
-- otherwise a measurement of this folder alone.
local function analyze(page)
	local row = watched(page)
	if not row or row.missing or not row.path or group(page, row) then return end
	local breakdown = row.resourceId and page.storage.breakdowns[row.resourceId]
	if breakdown then page.analyzed = {key = row.key, entries = breakdown}; return end
	local measure = rawget(service(page), "analyzeFolder")
	if not measure then return end
	local analyzed = {key = row.key, loading = true}
	page.analyzed = analyzed
	measure(row.path, function(entries, failure)
		if page.analyzed ~= analyzed then return end
		analyzed.loading, analyzed.entries, analyzed.failure = false, entries or {}, failure
		page.services.refresh()
	end)
end

local function contents(page, row)
	local source = group(page, row)
	if source then
		local rows = Categories.rows(page.storage, source.id)
		for _, item in ipairs(rows) do item.resourceId, item.detail = item.id, item.policy or "" end
		return page.actions:annotate(rows), Model.plural(#source:getChildren(), "location") .. " Diskmap measures here. Open one to review it."
	end
	local analyzed = page.analyzed
	analyzed = analyzed and analyzed.key == row.key and analyzed or {}
	local rows, total = VolumeContents.rows(row.path, analyzed.entries)
	local detail = analyzed.loading and "Measuring…" or analyzed.failure
		or Model.size(total) .. " in " .. Model.plural(#rows, "item") .. " at the top level."
	return page.actions:annotate(rows), detail, analyzed.loading
end

local function menu(page, item)
	if not item then return {} end
	if item.resourceId then return page.actions:resource(item.resourceId) end
	return page.actions:folder(item)
end

return require("apps.diskmap.models.ListPage").class(function()
	return {id = "watched", layout = function(presented) return presented.shape end,
		queries = {showInFinder = true, openCategory = true}, menu = menu, actions = {
			showInFinder = function(page) service(page).reveal(watched(page).path) end,
			openCategory = function(page) page.services.open(category(page, watched(page)).id) end,
			unwatch = function(page)
				local entry = page.services.watchlist:find(key(page))
				if entry and page.services.watchlist:toggle(entry) then page.services.show("overview") end
			end,
			openContents = function(page, _, _, item)
				if not item then return end
				local resource = item.resourceId and page.storage.resources:find(item.resourceId)
				if resource then page.services.open(resource.id) else service(page).reveal(item.path) end
			end,
		}, load = function(page) analyze(page) end, unload = function(page) page.analyzed = nil end,
		present = function(_, _, page)
			local row = watched(page)
			page.header = row and {icon = row.icon, color = row.color, title = row.name}
			if not row then return {shape = {}} end
			local summary = {row.size, row.changeText}
			if row.path then table.insert(summary, Model.tilde(row.path, page.storage.home)) end
			local buttons = {}
			if row.path and not row.missing then table.insert(buttons, {id = "reveal", title = "Show in Finder", action = "showInFinder"}) end
			local open = category(page, row)
			if open then table.insert(buttons, {id = "openCategory", title = "Open " .. open.name .. "…", action = "openCategory"}) end
			table.insert(buttons, {id = "unwatch", title = "Stop Watching", systemImage = "eye.slash", action = "unwatch"})
			-- A category's locations differ by policy; a folder's children are
			-- already labeled Folder or File under their names.
			local shape = {summary = table.concat(summary, " · "), summaryId = "watchedSummary", buttons = buttons, footnote = FOOTNOTE}
			if row.missing or not (group(page, row) or row.path) then return {shape = shape} end
			local rows, detail, loading = contents(page, row)
			shape.sections = {{id = "contentsSection", title = "Contents", detail = detail, detailId = "contentsDetail",
				list = {id = "contents", menu = "rowMenu", activate = "openContents", detailColumn = group(page, row) ~= nil}}}
			return {shape = shape, lists = {contents = rows}, loading = {contents = loading}}
		end}
end)
