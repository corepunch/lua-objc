local Model = require("data.model")
local Format = require("apps.diskmap.helpers.Format")
local ChartNodes = require("apps.diskmap.helpers.ChartNodes")
local ListRoute = require("apps.diskmap.pages.ListRoute")
local Locations = require("apps.diskmap.models.Locations")
local Categories = require("apps.diskmap.models.Categories")

-- A category's locations as a page like any other list (`/category/macos`):
-- every measured location under it, largest first, filtered by impact, as a
-- list or as rings or rectangles. A row's menu holds what can be done with
-- it (Keep, Show in Finder, its owner's removal); a row that lives on a page
-- of its own (Simulators, Projects) says so and opens it.
local routes = {}

local LAYOUT = {
	summaryId = "categorySummary",
	sections = {{title = "Locations", detailId = "categoryDetail",
		filters = {id = "filter", options = Categories.impacts},
		empties = {{id = "categoryEmpty", title = "No Matching Locations", systemImage = "tray",
			description = "Nothing in this category has this impact."}},
		panelId = "categoryList", chart = true,
		list = {id = "locations", menu = "rowMenu", activate = "open", detailColumn = true, fileIcons = true}}},
	footnote = {text = "Safe/rebuildable locations are recreated by the apps that own them. Review the rest before removing anything; Essential locations are part of a working system."},
}

local WAITING = {title = "Not Measured Yet", systemImage = "chart.bar.doc.horizontal",
	description = "Locations are listed once the scan has measured them."}

local category = ListRoute.extend({layout = LAYOUT, rootId = ""})
routes.category = category

-- `/category/developer?filter=Needs review`; `select` arrives with a location
-- opened from elsewhere (the Storage Map, Search) and selects its row.
function category:focus(params)
	local root = params.category and Locations:find(params.category)
	if params.category and not root then error("Unknown Diskmap category: " .. tostring(params.category), 0) end
	local rootId = root and root.id or ""
	if rootId ~= self.rootId then self.snapshotNote = nil end
	self.rootId = rootId
	self.filterIndex = params.filter and assert(Categories.impacts:index(params.filter), "Unknown impact filter") or 1
	self.selectedId = params.select
	-- `/category` alone lists every category's locations.
	self.header = root and {icon = root.icon, color = root.color, title = root.name}
		or {icon = "internaldrive.fill", color = "systemGray", title = "All Locations"}
end

function category:location()
	return {category = self.rootId ~= "" and self.rootId or nil, filter = self.filterIndex ~= 1 and Categories.impacts[self.filterIndex] or nil}
end

-- System Data says how many local snapshots it holds, the space it cannot
-- list as folders.
function category:load()
	if self.rootId ~= "system-data" then return end
	local rootId = self.rootId
	self.app.service.snapshotCount(function(count, dates)
		if count == nil or self.rootId ~= rootId then return end
		local note = count == 0 and "No local snapshots" or Format.plural(count, "local snapshot")
		if count > 0 and dates and #dates > 0 then
			local shown = {}
			for index = math.max(1, #dates - 3), #dates do table.insert(shown, (dates[index]:match("TimeMachine%.(.+)%.local$"))) end
			note = note .. " · " .. table.concat(shown, ", ") .. (#dates > #shown and " …" or "")
		end
		self.snapshotNote = note
		self.app.refresh()
	end)
end

-- A row that lives on a page of its own opens it; any other shows in the
-- Finder, as a Projects row does.
function category:activateRow(row)
	if row.opensElsewhere then self.app.open(row.id)
	elseif row.path then self.app.service.reveal(row.path) end
end

-- Rings and rectangles of the rows the filter shows: each group that owns
-- some of them, and its locations inside it.
function category:chart(presented)
	local top, owners = {}, {}
	for _, row in ipairs(presented.lists.locations) do
		local ownerId = row.ownerId ~= self.rootId and row.ownerId or nil
		local leaf = {id = row.id, name = row.name, bytes = row.bytes, size = row.size, color = row.color,
			hatched = row.impact == "Safe/rebuildable"}
		if not ownerId then
			table.insert(top, leaf)
		else
			local owner = owners[ownerId]
			if not owner then
				local location = Locations:find(ownerId)
				owner = {id = ownerId, name = row.owner, color = location and location.color, bytes = 0, children = {}, leaf = false}
				owners[ownerId] = owner
				table.insert(top, owner)
			end
			owner.bytes = owner.bytes + (row.bytes or 0)
			table.insert(owner.children, leaf)
		end
	end
	for _, row in ipairs(top) do if row.children then row.size = Format.size(row.bytes) end end
	table.sort(top, function(a, b) return (a.bytes or 0) > (b.bytes or 0) end)
	return ChartNodes.build(top, Categories:hues(top), 2, Categories.mapMinimumShare)
end

function category:present()
	if self.app.scanning() then return {waiting = WAITING} end
	local home, pages = Model.db.home, self.app.pages
	local rootId = self.rootId ~= "" and self.rootId or nil
	local rows = Categories:leafRows(rootId, Categories.impacts[self.filterIndex])
	table.sort(rows, function(a, b)
		if (a.bytes or -1) ~= (b.bytes or -1) then return (a.bytes or -1) > (b.bytes or -1) end
		return a.id < b.id
	end)
	for _, row in ipairs(rows) do
		local where = row.path and Format.tilde(row.path, home) or "Managed by macOS"
		row.subtitle = row.owner and row.ownerId ~= self.rootId and (row.owner .. " · " .. where) or where
		local destination = row.opensElsewhere and Locations:destination(row.id)
		local elsewhere = destination and destination.page and pages[destination.page]
		row.detail = row.kept and "Kept" or elsewhere and ("On " .. elsewhere.title) or row.impact
	end
	local all, bytes = Categories:leafRows(rootId), 0
	for _, row in ipairs(all) do bytes = bytes + (row.bytes or 0) end
	local summary = Format.size(bytes) .. " in " .. Format.plural(#all, "location")
	if self.snapshotNote then summary = summary .. " · " .. self.snapshotNote end
	return {lists = {locations = self.rowActions:annotate(rows)},
		hidden = {categoryEmpty = #rows > 0, categoryList = #rows == 0},
		texts = {categorySummary = summary, categoryDetail = "Largest first. A row's menu keeps, reveals or removes it."}}
end

return routes
