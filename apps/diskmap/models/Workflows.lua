local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Categories = require("apps.diskmap.helpers.Categories")
local Cleanup = require("apps.diskmap.helpers.Cleanup")
local Status = require("apps.diskmap.helpers.Status")
local Knowledge = require("apps.diskmap.knowledge.Workflows")

-- The kinds of work (knowledge/Workflows.lua), one row each, and each kind's
-- storage presented as sections of catalog rows. Developer, Music
-- Production, Video Production and the rest differ only in their entry:
--
--   Workflows:find("music"):presentation(query)
local Workflows, Workflow = Model:extend("workflows", {source = function() return Knowledge.list end,
	visibleBytes = Knowledge.visibleBytes})

local POLICY = {Rebuildable = "Rebuildable", Essential = "Keep", ["System managed"] = "System managed"}

-- A page row from a category row (Categories.rows): nothing for a location
-- that is empty, absent, left out of the scan or never measured.
local function pageRow(model, value)
	local group = value.children ~= nil
	local row = {id = value.id, name = value.name, subtitle = value.subtitle, icon = value.icon or "doc",
		color = value.color or "systemGray", appIcon = value.appIcon, path = value.path, bytes = value.bytes or 0, size = value.size,
		calculating = value.calculating == true, status = value.status, group = group,
		detail = model.kept[value.id] and "Kept" or group and "Group" or POLICY[value.policy] or "Review"}
	if row.status == "complete" and row.bytes == 0 then return nil end
	if row.status == "notMeasured" or row.status == "excluded" then return nil end
	Status.apply(row)
	return row
end

-- The category rows a section lists, in catalog order.
local function sectionValues(model, section)
	local values = {}
	for _, id in ipairs(section.roots or {}) do
		-- Build folders roll up into one row per ecosystem ("Node modules").
		for _, value in ipairs(Locations:find(id) and Categories.rows(id) or {}) do
			if value.children == nil or value.id:match("^build%-") then table.insert(values, value) end
		end
	end
	for _, id in ipairs(section.groups or {}) do
		for _, value in ipairs(Locations:find(id) and Categories.rows(id) or {}) do table.insert(values, value) end
	end
	for _, id in ipairs(section.items or {}) do
		table.insert(values, (Categories.row(id)))
	end
	return values
end

local function leaves(resource, into)
	if resource:isLeaf() then into[resource.id] = true; return end
	into[resource.id] = true
	for _, child in ipairs(resource:children()) do leaves(child, into) end
end

-- Page presentation: sections of rows, largest first, with share bars
-- compared across the whole page so sections can be read against each other.
-- `rebuildable` totals the cleanup suggestions among the page's rows.
function Workflow:presentation(query)
	local model = Model.db
	local needle = (query or ""):lower()
	local sections, largest, total, calculating, covered = {}, 0, 0, false, {}
	for _, section in ipairs(self.sections) do
		local rows = {}
		for _, value in ipairs(sectionValues(model, section)) do
			local row = pageRow(model, value)
			if row and (needle == "" or (row.name .. " " .. (row.subtitle or "") .. " " .. (row.path or "")):lower():find(needle, 1, true)) then
				table.insert(rows, row)
				leaves(Locations:find(row.id), covered)
			end
		end
		table.sort(rows, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.name < b.name end)
		local bytes = 0
		for _, row in ipairs(rows) do
			bytes = bytes + row.bytes; largest = math.max(largest, row.bytes)
			calculating = calculating or row.calculating
		end
		total = total + bytes
		if #rows > 0 then
			table.insert(sections, {id = section.id, title = section.title, detail = section.detail, rows = rows,
				bytes = bytes, size = Format.size(bytes)})
		end
	end
	for _, section in ipairs(sections) do
		for _, row in ipairs(section.rows) do
			row.relative = largest > 0 and row.bytes / largest or 0
			row.shareText = Format.percent(row.bytes, total)
		end
	end
	local rebuildable = 0
	for _, suggestion in ipairs(Cleanup.suggestions()) do
		if covered[suggestion.id] and suggestion.impact == "Safe/rebuildable" then rebuildable = rebuildable + suggestion.bytes end
	end
	return {sections = sections, total = Format.size(total), bytes = total, rebuildable = rebuildable,
		rebuildableSize = Format.size(rebuildable), calculating = calculating}
end

-- Whether this Mac does this kind of work: one of the workflow's markers
-- exists (`exists(path)`), or its locations measure at least its
-- `visibleBytes`. A total still being measured only grows, so reaching the
-- threshold early already proves the data is there.
function Workflow:marked(exists)
	local model = Model.db
	for _, marker in ipairs(self.markers or {}) do
		if exists((marker:gsub("^~", model.home))) then return true end
	end
	return false
end

function Workflow:measured()
	local model = Model.db
	local bytes = 0
	for _, section in ipairs(self.sections) do
		for _, value in ipairs(sectionValues(model, section)) do bytes = bytes + (value.bytes or 0) end
	end
	return bytes >= (self.visibleBytes or Workflows.visibleBytes)
end

function Workflow:present(exists)
	local model = Model.db
	return exists ~= nil and self:marked(exists) or self:measured()
end

-- The sidebar badge: the page's own total once nothing is being measured.
function Workflow:badge()
	local model = Model.db
	local data = self:presentation()
	if data.bytes > 0 and not data.calculating then return data.total end
end

return Workflows
