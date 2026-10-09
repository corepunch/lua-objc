local Model = require("data.model")
local Applications = require("apps.diskmap.models.Applications")
local Files = require("apps.diskmap.models.Files")
local Filesystem = require("apps.diskmap.helpers.Filesystem")
local FileKind = require("apps.diskmap.helpers.FileKind")
local Format = require("apps.diskmap.helpers.Format")
local Guide = require("apps.diskmap.helpers.Guide")
local Help = require("apps.diskmap.helpers.Help")
local Inventories = require("apps.diskmap.models.Inventories")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Locations = require("apps.diskmap.models.Locations")
local Projects = require("apps.diskmap.models.Projects")
local Search = require("apps.diskmap.helpers.Search")
local Simulators = require("apps.diskmap.helpers.Simulators")

-- Search: what the toolbar's search field finds across the whole store, as
-- Spotlight lists its results by kind. Typing opens this page and clearing
-- the field returns to the page it left; no other page filters by text.
-- Every kind of row is a group below: the rows that match, the page or
-- action that opens one, and its menu. A row opens where Diskmap shows it:
-- a location by its own destination, a file or app in Finder, a topic on its
-- page with the topic open.
local routes = {}

-- A long group shows its largest results; its page lists them all.
local RESULTS = {limit = 25}

local function copy(row, extra)
	local result = {}
	for key, value in pairs(row) do result[key] = value end
	for key, value in pairs(extra or {}) do result[key] = value end
	return result
end

-- A row with a folder on disk has the folder's menu; one without has only Open.
local function revealable(page, row, open)
	if row.path then return page.rowActions:folder(row) end
	return {{title = "Open", systemImage = "arrow.right.circle", action = function() open(page, row) end}}
end

local function showing(id, params)
	return function(page) page.app.show(id, params) end
end

-- The groups in the order they are listed. `rows(page, needle)` answers the
-- matching rows; `open(page, row)` and `menu(page, row)` act on one. `list`
-- adds ResourceList arguments (a detail column, file icons).
local GROUPS = {
	{id = "pages", title = "Pages",
		rows = function(page, needle)
			local present, rows = page.app.workflowsPresent(), {}
			for _, entry in ipairs(page.app.manifest.order) do
				local workflow = entry.attrs.workflow
				if entry.listed and (not workflow or present[workflow])
					and Search.matches(needle, entry.title, entry.attrs.sidebar, entry.section.title) then
					table.insert(rows, {id = entry.id, name = entry.title, subtitle = entry.section.title or "Diskmap",
						icon = entry.icon, color = entry.color, page = entry.id, pageName = entry.title})
				end
			end
			return rows
		end,
		open = function(page, row) page.app.show(row.page) end},
	{id = "locations", title = "Locations", list = {status = true},
		rows = function(page, needle, state) return Search.filter(Locations:largest(state.disk), needle, {"name", "subtitle", "path"}) end,
		open = function(page, row) page.app.open(row.id) end,
		menu = function(page, row) return page.rowActions:resource(row.id) end},
	{id = "files", title = "Large Files", list = {detailColumn = true, fileIcons = true},
		rows = function(page, needle) return page.rowActions:annotate(Search.filter(Files:rows("All"), needle, {"name", "path", "owner"})) end,
		open = function(page, row) page.app.service.reveal(row.path) end,
		menu = function(page, row) return page.rowActions:file(row) end},
	{id = "applications", title = "Applications", list = {detailColumn = true},
		rows = function(page, needle) return Search.filter(Applications:rows("All"), needle, {"name", "bundleId"}) end,
		open = function(page, row) page.app.service.reveal(row.path) end,
		menu = function(page, row) return page.rowActions:application(row) end},
	{id = "leftovers", title = "Possible App Leftovers", list = {detailColumn = true},
		rows = function(page, needle) return page.rowActions:annotate(Search.filter(Applications:leftovers(), needle, {"name", "subtitle"})) end,
		open = showing("applications"),
		menu = function(page, row) return page.rowActions:folder(row, nil, Applications.leftoverItem(row)) end},
	{id = "projects", title = "Projects", list = {detailColumn = true},
		rows = function(page, needle)
			local rows = {}
			for _, group in ipairs(Search.filter(Projects:groups(), needle, {"name", "path", "artifactText"})) do
				table.insert(rows, copy(group, {id = group.path, detail = group.gitText, icon = "folder.fill", color = group.dirty and "systemOrange" or "systemGreen",
					subtitle = Format.tilde(group.path, Model.db.home) .. " · " .. group.artifactText}))
			end
			return rows
		end,
		open = showing("projects"), menu = revealable},
	{id = "simulators", title = "Simulators", list = {detailColumn = true},
		rows = function(page, needle)
			local stock = Inventories:state("simulators")
			if not stock.loaded then return {} end
			local rows = {}
			for _, device in ipairs(Search.filter(Simulators.rows(stock.inventory), needle, {"name", "runtime", "id"})) do
				table.insert(rows, copy(device, {subtitle = device.runtime, detail = device.lastUse}))
			end
			return rows
		end,
		open = showing("simulators"), menu = revealable},
	{id = "worktrees", title = "Worktrees", list = {detailColumn = true},
		rows = function(page, needle)
			local stock = Inventories:state("worktrees")
			if not stock.loaded then return {} end
			local rows = {}
			for _, row in ipairs(Search.filter(stock.rows, needle, {"name", "path", "subtitle"})) do table.insert(rows, copy(row)) end
			return rows
		end,
		open = showing("worktrees"), menu = revealable},
	{id = "kinds", title = "File Types", list = {detailColumn = true},
		rows = function(page, needle)
			if Files:state() ~= "loaded" then return {} end
			-- A kind is found by its name or one of its extensions (".dmg").
			local extension = needle:gsub("^%.", "")
			local found = {}
			for _, row in ipairs(Model.db.files.extensions) do
				if row.extension ~= "" and row.extension:lower():find(extension, 1, true) then
					found[(FileKind.byExtension[row.extension] or FileKind.other).id] = true
				end
			end
			local rows = {}
			for _, row in ipairs((Files:kinds())) do
				if found[row.id] or Search.matches(needle, row.name) then
					table.insert(rows, copy(row, {kindId = row.id, detail = Format.plural(Format.count(row.count), "file")}))
				end
			end
			return rows
		end,
		open = function(page, row) page.app.show("files", {filter = "All", kind = row.kindId}) end},
	{id = "guide", title = "Storage Guide",
		rows = function(page, needle)
			local rows = {}
			for _, topic in ipairs(Guide.search(needle)) do
				table.insert(rows, {id = topic.id, name = topic.title, subtitle = topic.chapter .. " · " .. topic.summary, icon = topic.icon, color = "systemTeal"})
			end
			return rows
		end,
		open = function(page, row) page.app.show("guide", {topic = row.id}) end},
	{id = "folders", title = "macOS Folders",
		rows = function(page, needle)
			local rows = {}
			for _, location in ipairs(Filesystem.search(needle)) do
				table.insert(rows, {id = location.id, name = location.name, subtitle = location.path .. " · " .. location.area, icon = location.icon, color = "systemGray"})
			end
			return rows
		end,
		open = showing("filesystem")},
	{id = "help", title = "Diskmap Help",
		rows = function(page, needle)
			local rows = {}
			for _, topic in ipairs(Help.search(needle)) do
				table.insert(rows, {id = topic.id, name = topic.title, subtitle = topic.chapter .. " · " .. topic.summary, icon = topic.icon, color = "systemBlue"})
			end
			return rows
		end,
		open = function(page, row) page.app.show("help", {topic = row.id}) end},
}
local BY_ID = {}
for _, group in ipairs(GROUPS) do BY_ID[group.id] = group end

local EMPTY = {id = "searchEmpty", title = "Search Diskmap", systemImage = "magnifyingglass",
	description = "Type a name or a path to find locations, files, apps, projects and help topics."}

local function layout(page, presented)
	local sections = {}
	for _, found in ipairs(presented.groups) do
		local list = copy(BY_ID[found.id].list or {}, {id = "results_" .. found.id, menu = "rowMenu", activate = "open"})
		table.insert(sections, {id = "section_" .. found.id, title = found.title, detail = found.detail, list = list})
	end
	local empty = #sections == 0 and EMPTY or nil
	if empty and page.needle then
		empty = {id = "searchNoResults", title = "No Results", systemImage = "magnifyingglass",
			description = "Nothing Diskmap measured or explains mentions “" .. page.query .. "”."}
	end
	return {sections = sections, empty = empty}
end

routes.search = ListRoute.extend({layout = layout})

function routes.search:present(state)
	self.query = state.query or ""
	self.needle = Search.needle(self.query)
	local groups, lists, count = {}, {}, 0
	if self.needle then
		for _, group in ipairs(GROUPS) do
			local rows = group.rows(self, self.needle, state)
			if #rows > 0 then
				count = count + #rows
				local detail = #rows > RESULTS.limit and string.format("The %d largest of %d", RESULTS.limit, #rows) or nil
				while #rows > RESULTS.limit do table.remove(rows) end
				-- Bars compare the results of one group, as on the group's page.
				local largest = 0
				for _, row in ipairs(rows) do largest = math.max(largest, row.bytes or 0) end
				for _, row in ipairs(rows) do
					row.result = group.id
					row.relative = row.bytes and largest > 0 and row.bytes / largest or nil
				end
				table.insert(groups, {id = group.id, title = group.title, detail = detail})
				lists["results_" .. group.id] = rows
			end
		end
	end
	return {groups = groups, lists = lists, subtitle = not self.needle and "Everything Diskmap measured and explains, in one search."
		or count == 0 and "No results" or (Format.plural(count, "result") .. " for “" .. self.query .. "”")}
end

function routes.search:activateRow(row)
	if row then BY_ID[row.result].open(self, row) end
end

function routes.search:menu(row)
	local group = BY_ID[row.result]
	if group.menu then return group.menu(self, row, group.open) end
	return {{title = "Open", systemImage = "arrow.right.circle", action = function() group.open(self, row) end}}
end

return routes
