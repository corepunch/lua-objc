local ns = require("AppKit")
local xml = require("ui.xml")
local Categories = require("apps.diskmap.models.Categories")
local Inspector = require("apps.diskmap.models.Inspector")
local InspectorController = require("apps.diskmap.controllers.InspectorController")
local Controller = {}; Controller.__index = Controller

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

function Controller.new(model, service, refresh, keep, simulators)
	return setmetatable({model = model, service = service, refresh = refresh, keep = keep, simulators = simulators,
		sortColumn = "size", sortAscending = false}, Controller)
end

function Controller:sortBy(column)
	if column ~= "name" and column ~= "impact" and column ~= "size" then return end
	if self.sortColumn == column then self.sortAscending = not self.sortAscending
	else self.sortColumn = column; self.sortAscending = true end
	self:update()
end
function Controller:close()
	if self.sheet then ns.dismiss(self.sheet); self.sheet = nil end
	if self.scope then self.scope:close(); self.scope = nil end
	self.refs = nil
end
function Controller:select(id)
	self.selectedId = id
	local row, detail = self.model.resources:find(id), Inspector.details(self.model, id)
	if not detail then return end
	local refs = self.refs
	refs.detail.text = row.consequence or row.subtitle; refs.path.text = detail.location
	refs.manage.hidden = row.action == "finder"
	refs.manage.title = detail.manageTitle; refs.manage.enabled = detail.canManage
	refs.reveal.enabled = row.path ~= nil
	refs.keep.enabled = true; refs.keep.title = detail.keepTitle
	self.sheet:layout()
end
function Controller:update()
	if not self.refs then return end
	local total, selected = 0, self.selectedId
	local selectionVisible = false
	for index, filter in ipairs(self.filters) do
		local rows = Categories.managementRows(self.model, self.rootId, self.query, filter)
		rows = sortRows(rows, self.sortColumn, self.sortAscending)
		local list = self.refs["rows" .. index]
		list:replaceRows(rows)
		list:setSortIndicator(self.sortColumn, self.sortAscending)
		if self.refs.tabs.selectedTabViewItem.label == filter then
			for offset, row in ipairs(rows) do if row.id == selected then
				selectionVisible = true; self.refs["rows" .. index]:selectRow(offset - 1)
			end end
		end
		if index == 1 then total = #rows end
	end
	self.refs.status.text = total == 0 and "No matching resources. Try another name or path." or total .. " resources · Review amounts are not guaranteed reclaimable space."
	self.refs.manage.enabled = false; self.refs.reveal.enabled = false; self.refs.keep.enabled = false
	self.selectedId = nil
	if selectionVisible then self:select(selected) end
end
function Controller:open(parent, id, filter)
	self:close(); self.rootId = id; self.query = ""
	self.filters = {"All", "Safe/rebuildable", "Needs review", "Essential to keep"}
	self.scope = ns.Scope.new()
	ns.Scope.withScope(self.scope, function()
		self.sheet, self.refs = xml.renderFile("apps/diskmap/views/Management.etlua", {
			title = self.model.resources:find(id) and self.model.resources:find(id).name or "Safe reclaim potential", filters = self.filters,
			actions = {
				search = function(value) self.query = value; self:update() end,
				done = function() self:close() end,
				reveal = function() local row = self.model.resources:find(self.selectedId); if row and row.path then self.service.reveal(row.path) end end,
				keep = function() if self.selectedId then local selected = self.selectedId; self.keep(selected); self:select(selected) end end,
				manage = function()
					local row = self.model.resources:find(self.selectedId); if not row then return end
					if row.action == "simulators" then self:close(); self.simulators(); return end
					local inspector = InspectorController.new(self.model, self.service, self.refresh)
					inspector:select(row.id); inspector:manage()
				end,
			}}, ns)
		self.refs.done.keyEquivalent = "\r"
		self.sheet.defaultButtonCell = self.refs.done.cell
		for index in ipairs(self.filters) do
			local list = self.refs["rows" .. index]
			list:onRowSelect(function(_, _, row) if row then self:select(row.id) end end)
			list:onColumnSort(function(_, column) self:sortBy(column) end)
		end
		self.refs.tabs:onChange(function() self.selectedId = nil; self.refs.manage.enabled = false; self.refs.reveal.enabled = false; self.refs.keep.enabled = false end)
	end)
	self:update()
	if id == "system-data" and self.service.snapshotCount then
		local sheet = self.sheet
		self.service.snapshotCount(function(count, dates)
			if count == nil or self.sheet ~= sheet or not self.refs then return end
			local note = count == 0 and "No local snapshots" or (tostring(count) .. " local snapshots")
			if count > 0 and dates and #dates > 0 then
				local shown = {}; for index = math.max(1, #dates - 3), #dates do shown[#shown + 1] = dates[index]:match("TimeMachine%.(.+)%.local$") end
				note = note .. " · " .. table.concat(shown, ", ") .. (#dates > #shown and " …" or "")
			end
			self.refs.status.text = note .. " (system managed) · " .. self.refs.status.text
			self.sheet:layout()
		end)
	end
	if filter then for index, name in ipairs(self.filters) do if name == filter then self.refs.tabs:selectTab(index - 1) end end end
	ns.presentSheet(self.sheet, parent); ns.focus(self.sheet, self.refs.search)
end
return Controller
