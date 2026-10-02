local SheetPage = require("apps.diskmap.SheetPage")
local Categories = require("apps.diskmap.models.Categories")
local Destinations = require("apps.diskmap.models.Destinations")
local Inspector = require("apps.diskmap.models.Inspector")
local Manage = require("apps.diskmap.models.Manage")
local Selection = require("apps.diskmap.models.Selection")

-- A category's list of locations, as a sheet over the window: one list per
-- impact tab, searchable and sortable, with the selected location's
-- actions below. `services.open(id)` opens a resource wherever Destinations
-- sends it; a row that lives on a page or sheet of its own leaves this one.
local ManagementSheet = SheetPage.define({id = "management", view = "Management", width = 620, height = 640})

ManagementSheet.filters = {"All", "Safe/rebuildable", "Needs review", "Essential to keep"}
ManagementSheet.queries = {reveal = true}

local function sortRows(rows, column, ascending)
	local function value(row)
		if column == "size" then return row.bytes end
		return row[column]
	end
	table.sort(rows, function(left, right)
		local a, b = value(left), value(right)
		if a == nil or b == nil then
			if a == nil and b ~= nil then return false end
			if a ~= nil and b == nil then return true end
		else
			if type(a) == "string" then a, b = a:lower(), b:lower() end
			if a ~= b then
				if ascending then return a < b end
				return a > b
			end
		end
		local leftName, rightName = left.name:lower(), right.name:lower()
		if leftName ~= rightName then return leftName < rightName end
		return left.id < right.id
	end)
	return rows
end

function ManagementSheet.new(_, services)
	return setmetatable({services = services, service = services.service, storage = services.model}, ManagementSheet)
end

-- `options.select` is the location to select and scroll to; `options.filter`
-- the impact tab to show. The list always opens largest first.
function ManagementSheet:open(parent, id, options)
	options = options or {}
	self.rootId, self.query, self.sortColumn, self.sortAscending = id, "", "size", false
	self.selectedId, self.tab, self.openTab, self.snapshotNote = options.select, options.filter or "All", options.filter, nil
	SheetPage.open(self, parent)
end

-- While a scan measures, the sheet shows one progress state in place of its
-- lists; the locations appear once their sizes are known.
function ManagementSheet:data()
	local resources, scanning = self.storage.resources, self.services.scanning()
	local lists, tabRows, loading = {}, {}, {}
	for index, filter in ipairs(self.filters) do
		local rows = scanning and {} or sortRows(Categories.managementRows(self.storage, self.rootId, self.query, filter),
			self.sortColumn, self.sortAscending)
		lists["rows" .. index], tabRows[filter], loading["rows" .. index] = rows, rows, scanning
	end
	-- Only a row of the tab that shows can stay selected.
	local selected = self.selectedId
	if not scanning then
		local visible
		for _, row in ipairs(tabRows[self.tab] or {}) do if row.id == selected then visible = true end end
		if not visible then selected = nil end
	end
	self.selectedId, self.tabRows = selected, tabRows
	local total = #lists.rows1
	local summary = scanning and "Measuring…" or total == 0 and "No matching resources."
		or total .. (total == 1 and " resource" or " resources")
	local row = selected and not scanning and resources:find(selected)
	local detail = row and Inspector.details(self.storage, selected)
	local root = resources:find(self.rootId)
	return {
		title = root and root.name or "Safe reclaim potential", category = Inspector.details(self.storage, self.rootId),
		filters = self.filters, manageTitle = detail and detail.manageTitle or "Review",
		lists = lists, loading = loading,
		texts = {status = detail and detail.location or (self.snapshotNote and self.snapshotNote .. " · " .. summary or summary),
			keep = detail and detail.keepTitle or "Keep"},
		hidden = {manage = row and row.action == "finder" or false},
		disabled = {manage = not (detail and detail.canManage), reveal = not (row and row.path), keep = detail == nil},
	}
end

-- After a draw: the sort arrows, the tab the person asked for, and the
-- selected row in the tab that shows.
function ManagementSheet:sync(refs)
	for index, filter in ipairs(self.filters) do
		local list = refs["rows" .. index]
		list:setSortIndicator(self.sortColumn, self.sortAscending)
		if filter == self.tab then Selection.show(list, self.tabRows[filter], self.selectedId) end
	end
	if self.openTab then
		for index, filter in ipairs(self.filters) do
			if filter == self.openTab then refs.tabs:selectTab(index - 1) end
		end
		self.openTab = nil
	end
end

-- The count of local snapshots joins the status line of System Data.
function ManagementSheet:activate()
	if self.rootId ~= "system-data" or not self.service.snapshotCount then return end
	local sheet = self.sheet
	self.service.snapshotCount(function(count, dates)
		if count == nil or self.sheet ~= sheet then return end
		local note = count == 0 and "No local snapshots" or (tostring(count) .. " local snapshots")
		if count > 0 and dates and #dates > 0 then
			local shown = {}; for index = math.max(1, #dates - 3), #dates do table.insert(shown, (dates[index]:match("TimeMachine%.(.+)%.local$"))) end
			note = note .. " · " .. table.concat(shown, ", ") .. (#dates > #shown and " …" or "")
		end
		self.snapshotNote = note
		self:draw()
	end)
end

function ManagementSheet:search(value) self.query = value or "" end

function ManagementSheet:sortBy(column)
	if column ~= "name" and column ~= "impact" and column ~= "size" then return end
	if self.sortColumn == column then self.sortAscending = not self.sortAscending
	else self.sortColumn = column; self.sortAscending = true end
	self:draw()
end

function ManagementSheet:sort(_, column) self:sortBy(column) end
function ManagementSheet:select(_, _, row) if row then self.selectedId = row.id end end

function ManagementSheet:tabChanged()
	self.tab, self.selectedId = self.refs.tabs.selectedTabViewItem.label, nil
end

function ManagementSheet:categoryRefresh() self.services.rescan() end
function ManagementSheet:categoryKeep() self.services.keep(self.rootId) end
function ManagementSheet:keep() if self.selectedId then self.services.keep(self.selectedId) end end

function ManagementSheet:reveal()
	local row = self.storage.resources:find(self.selectedId)
	if row and row.path then self.service.reveal(row.path) end
end

function ManagementSheet:review(id, manage)
	local row = self.storage.resources:find(id)
	if not row then return end
	if Destinations.elsewhere(self.storage, id) then self.services.open(id); return end
	if not manage then return end
	local inspector = Manage.new(self.storage, self.service, self.services.rescan)
	inspector:select(row.id); inspector:manage()
end

function ManagementSheet:manage() self:review(self.selectedId, true) end
function ManagementSheet:reviewRow(_, _, row) if row then self:review(row.id) end end

return ManagementSheet
