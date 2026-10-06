local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Projects = require("apps.diskmap.models.Projects")
local Categories = require("apps.diskmap.models.Categories")
local ChartNodes = require("apps.diskmap.helpers.ChartNodes")
local Locations = require("apps.diskmap.models.Locations")

local routes = {}

local LAYOUT = {
	summary = "Build data your projects can recreate.", summaryId = "projectsSummary",
	buttons = {{id = "addFolder", title = "Add Folder…", systemImage = "plus", action = "addFolder", help = "Search another folder for projects"}},
	sections = {{title = "Build folders", detailId = "projectRoots",
		filters = {id = "filter", options = Projects.filters},
		buttons = {{id = "markStale", title = "Mark Old Build Data", systemImage = "plus.circle", action = "markStale",
			help = "Mark build data of projects with a clean git tree, untouched for three months"}},
		empties = {{id = "projectsEmpty", title = "No Build Folders Found", systemImage = "folder.badge.gearshape",
			description = "Projects appear here once Diskmap finds node_modules, target, .build and similar folders beside their project files."}},
		panelId = "projectsList", chart = true,
		list = {id = "projects", menu = "rowMenu", activate = "reveal", detailColumn = true}}},
	footnote = {text = "Only folders a project's tools create (node_modules, target, .build, …) are listed. Projects with uncommitted or unpushed work are never marked in bulk."},
}

local WAITING = {title = "Projects Not Found Yet", systemImage = "folder.badge.gearshape", description = "Build folders are listed when the scan finishes."}

-- A project is marked when all of its generated folders are.
local function isMarked(page, group)
	for _, artifact in ipairs(group.artifacts) do
		if not page.rowActions:isMarked(artifact.path) then return false end
	end
	return #group.artifacts > 0
end

-- Whether every generated folder is covered by a mark, and the enclosing
-- marked folder if one covers them from above.
local function included(page, group)
	local enclosing
	for _, artifact in ipairs(group.artifacts) do
		local item, exact = page.rowActions:covering(artifact.path)
		if not item then return false end
		if not exact then enclosing = enclosing or item end
	end
	return #group.artifacts > 0, enclosing
end


local function mark(page, group)
	if isMarked(page, group) then page.app.basket:removeAll(Projects.items(group))
	else page.rowActions:markAll(Projects.items(group)) end
end

-- Old build data of a project whose git tree is clean.
local function stale(page)
	local found = {}
	for _, group in ipairs(Projects:groups(Projects.filters[2])) do
		if type(group.git) == "table" and group.git.clean and not included(page, group) then table.insert(found, group) end
	end
	return found
end

local function rootsText(page)
	local roots = {"~/Developer"}
	for _, root in ipairs(Model.db.projectRoots or {}) do table.insert(roots, Format.tilde(root, Model.db.home)) end
	return table.concat(roots, ", ")
end

-- The Projects page: generated build folders found beside their project
-- markers, grouped by project with git state and age. Marking a project marks
-- its generated folders, never its sources.
routes.projects = ListRoute.extend({layout = LAYOUT,
	load = function(page) page.app.inventories:load("projects") end,
	-- A project's menu marks all of its build folders at once; its sources are
	-- never offered.
	menu = function(page, group)
		local actions, service = page.rowActions, page.app.service
		local all, enclosing = included(page, group)
		if all and enclosing then
			return {{title = "Included through Marked Folder — Review…", systemImage = "folder.badge.checkmark",
				action = function() page.app.openReview(enclosing.path) end}, actions:reveal(group.path), actions:copyPath(group.path)}
		end
		local marked = isMarked(page, group)
		local items = {{title = marked and "Unmark Build Data" or "Mark Build Data for Cleanup", systemImage = marked and "minus.circle" or "plus.circle",
			action = function() mark(page, group) end}}
		for _, artifact in ipairs(group.artifacts) do
			table.insert(items, {title = "Show " .. artifact.name .. " (" .. artifact.size .. ")", systemImage = "folder",
				action = function() service.reveal(artifact.path) end})
		end
		table.insert(items, {separator = true})
		table.insert(items, actions:reveal(group.path))
		table.insert(items, actions:copyPath(group.path))
		return items
	end,
	-- Rings and rectangles: each project, and its build folders inside it.
	chart = function(_, presented)
		local top = {}
		for _, group in ipairs(presented.lists.projects) do
			local folders = {}
			for _, artifact in ipairs(group.artifacts) do
				table.insert(folders, {id = artifact.id, name = artifact.name, bytes = artifact.bytes, size = artifact.size})
			end
			table.insert(top, {id = group.id, name = group.name, bytes = group.bytes, size = group.size, color = group.color, children = folders, leaf = false})
		end
		return ChartNodes.build(top, Categories:hues(top), 2, Categories.mapMinimumShare)
	end,
	-- A project or one of its build folders opens in the Finder, as a
	-- double-clicked row does.
	activateRow = function(page, row) page.app.service.reveal(row.path) end,
	activateNode = function(page, id)
		local folder = Locations:find(id)
		if folder and folder.path then page.app.service.reveal(folder.path) end
	end,
	markStale = function(page)
		return page.rowActions:bulk(stale(page), function() return true end, Projects.items)
	end,
	addFolder = function(page)
		local storage, service = Model.db, page.app.service
		local path = service.pickFolder("Choose a Folder with Projects")
		if not path then return end
		storage.projectRoots = storage.projectRoots or {}
		for _, root in ipairs(storage.projectRoots) do if root == path then return end end
		table.insert(storage.projectRoots, path)
		if not service.saveFolders("projects", storage.projectRoots) then service.showError("Could not save project folders", "Try again.") end
		page.app.rescan()
	end,
	present = function(page)
		local model = Model.db
		Model.db.projectInfo = Model.db.projectInfo or {}
		-- Nothing is listed until the scan has found the projects and git has
		-- told their state, one project at a time.
		if model.scan.running then return {waiting = WAITING} end
		for _, group in ipairs(Projects:groups(Projects.filters[1])) do
			if not Model.db.projectInfo[group.path] then return {computing = "Reading the state of your projects…"} end
		end
		-- Rows are the groups themselves, so menus receive a project's
		-- artifacts. A project is marked when all its build folders are.
		local rows = Projects:groups(Projects.filters[page.filterIndex])
		for _, group in ipairs(rows) do
			group.id, group.detail = group.path, group.gitText
			group.subtitle = Format.tilde(group.path, model.home) .. " · " .. group.artifactText .. " · " .. group.ageText
			group.icon, group.color = "folder.fill", group.dirty and "systemOrange" or "systemGreen"
			if isMarked(page, group) then
				group.marked = true
			elseif included(page, group) then
				group.included = true
			end
		end
		local all, bytes = Projects:groups(Projects.filters[1]), 0
		for _, group in ipairs(all) do bytes = bytes + group.bytes end
		return {lists = {projects = page.rowActions:annotate(rows)}, hidden = {projectsEmpty = #all > 0, projectsList = #all == 0},
			disabled = {markStale = #stale(page) == 0}, texts = {projectRoots = "Project folders: " .. rootsText(page) .. ".",
			projectsSummary = #all == 0 and "No project build folders found yet. Add the folders where you keep code."
				or (Format.size(bytes) .. " of build data in " .. Format.plural(#all, "project"))}}
	end})

return routes
