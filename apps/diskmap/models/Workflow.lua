local Model = require("apps.diskmap.Model")
local Categories = require("apps.diskmap.models.Categories")
local Cleanup = require("apps.diskmap.models.Cleanup")
local Status = require("apps.diskmap.models.Status")
local Workflows = require("apps.diskmap.knowledge.Workflows")
local Workflow = {}

-- One kind of work's storage (knowledge/Workflows.lua), presented as
-- sections of catalog rows. Developer, Music Production, Video Production
-- and the rest differ only in their table entry.

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
		for _, value in ipairs(model.resources:find(id) and Categories.rows(model, id) or {}) do
			if value.children == nil or value.id:match("^build%-") then table.insert(values, value) end
		end
	end
	for _, id in ipairs(section.groups or {}) do
		for _, value in ipairs(model.resources:find(id) and Categories.rows(model, id) or {}) do table.insert(values, value) end
	end
	for _, id in ipairs(section.items or {}) do
		table.insert(values, (Categories.row(model, id)))
	end
	return values
end

local function leaves(resource, into)
	if resource:isLeaf() then into[resource.id] = true; return end
	into[resource.id] = true
	for _, child in ipairs(resource:getChildren()) do leaves(child, into) end
end

-- Page presentation: sections of rows, largest first, with share bars
-- compared across the whole page so sections can be read against each other.
-- `rebuildable` totals the cleanup suggestions among the page's rows.
function Workflow.presentation(model, workflow, query)
	local needle = (query or ""):lower()
	local sections, largest, total, calculating, covered = {}, 0, 0, false, {}
	for _, section in ipairs(workflow.sections) do
		local rows = {}
		for _, value in ipairs(sectionValues(model, section)) do
			local row = pageRow(model, value)
			if row and (needle == "" or (row.name .. " " .. (row.subtitle or "") .. " " .. (row.path or "")):lower():find(needle, 1, true)) then
				table.insert(rows, row)
				leaves(model.resources:find(row.id), covered)
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
				bytes = bytes, size = Model.size(bytes)})
		end
	end
	for _, section in ipairs(sections) do
		for _, row in ipairs(section.rows) do
			row.relative = largest > 0 and row.bytes / largest or 0
			row.shareText = Model.percent(row.bytes, total)
		end
	end
	local rebuildable = 0
	for _, suggestion in ipairs(Cleanup.suggestions(model)) do
		if covered[suggestion.id] and suggestion.impact == "Safe/rebuildable" then rebuildable = rebuildable + suggestion.bytes end
	end
	return {sections = sections, total = Model.size(total), bytes = total, rebuildable = rebuildable,
		rebuildableSize = Model.size(rebuildable), calculating = calculating}
end

-- Whether this Mac does this kind of work: one of the workflow's markers
-- exists (`exists(path)`), or its locations measure at least its
-- `visibleBytes`. A total still being measured only grows, so reaching the
-- threshold early already proves the data is there.
function Workflow.marked(model, workflow, exists)
	for _, marker in ipairs(workflow.markers or {}) do
		if exists((marker:gsub("^~", model.home))) then return true end
	end
	return false
end

function Workflow.measured(model, workflow)
	local bytes = 0
	for _, section in ipairs(workflow.sections) do
		for _, value in ipairs(sectionValues(model, section)) do bytes = bytes + (value.bytes or 0) end
	end
	return bytes >= (workflow.visibleBytes or Workflows.visibleBytes)
end

function Workflow.present(model, workflow, exists)
	return exists ~= nil and Workflow.marked(model, workflow, exists) or Workflow.measured(model, workflow)
end

-- The sidebar badge: the page's own total once nothing is being measured.
function Workflow.badge(model, workflow)
	local data = Workflow.presentation(model, workflow)
	if data.bytes > 0 and not data.calculating then return data.total end
end

-- The page a ResourcePageController presents for `workflow`.
function Workflow.page(workflow)
	local links, buttons = {}, {}
	for index, link in ipairs(workflow.links or {}) do
		links["link_" .. index] = {open = link.open}
		table.insert(buttons, {id = "link_" .. index, title = link.title, action = "link_" .. index})
	end
	return {view = "Workflow", present = function(model, state)
		local data = Workflow.presentation(model, workflow, state.query)
		local structure, lists, texts = {}, {}, {}
		for _, section in ipairs(data.sections) do
			table.insert(structure, {id = section.id, title = section.title, detail = section.detail})
			lists["list_" .. section.id] = section.rows
			texts["size_" .. section.id] = section.size
		end
		texts.summary = data.calculating and ("Measuring " .. workflow.noun .. "…")
			or (data.total .. " " .. workflow.summary
				.. (data.rebuildable > 0 and (" · " .. data.rebuildableSize .. " rebuildable now") or ""))
		return {template = {workflow = {id = workflow.id, name = workflow.name, icon = workflow.icon, color = workflow.color,
				empty = workflow.empty, footnote = workflow.footnote,
				emptyTitle = data.calculating and ("Measuring " .. workflow.noun .. "…") or ("No " .. workflow.noun .. " found")},
				sections = structure, buttons = buttons},
			lists = lists, texts = texts, links = links}
	end}
end

return Workflow
