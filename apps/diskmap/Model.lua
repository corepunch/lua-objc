local Catalog = require("apps.diskmap.Catalog")
local Model = {}
function Model.size(bytes)
	if bytes == nil then return "Not measured" end
	if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
	if bytes >= 1e6 then return string.format("%.1f MB", bytes / 1e6) end
	return string.format("%.0f KB", bytes / 1000)
end
function Model.new(home)
	local self = {tree = Catalog.tree(home), byId = {}, leaves = {}, measurements = {}, kept = {}, scan = {}}
	local function index(rows, parent)
		for _, row in ipairs(rows) do
			row.parentId = parent and parent.id
			row.icon = row.icon or parent and parent.icon or "doc"
			row.color = row.color or parent and parent.color or "systemGray"
			row.appIcon = row.appIcon or parent and parent.appIcon
			self.byId[row.id] = row
			if row.children then index(row.children, row) else
				self.leaves[#self.leaves + 1] = row
				if row.measurement then self.measurements[row.id] = {status = row.measurement} end
			end
		end
	end
	index(self.tree)
	return self
end
function Model.rows(model, rootId, query)
	local needle = (query or ""):lower()
	local function build(source, inheritedMatch)
		local row = {}; for k, v in pairs(source) do if k ~= "children" then row[k] = v end end
		local matches = inheritedMatch or (source.name .. " " .. source.subtitle):lower():find(needle, 1, true) ~= nil
		local m = model.measurements[source.id] or {}
		row.bytes, row.status = m.bytes, m.status or "notMeasured"
		if source.children then
			row.children = {}; local total, measured, complete, attempted = 0, false, true, false
			for _, child in ipairs(source.children) do
				local value, visible = build(child, matches)
				if value.bytes then total = total + value.bytes; measured = true end
				if value.status ~= "complete" then complete = false end
				if value.status ~= "notMeasured" then attempted = true end
				if visible then row.children[#row.children + 1] = value end
			end
			row.bytes = measured and total or nil
			row.status = complete and "complete" or measured and "partial" or attempted and "denied" or "notMeasured"
			row.expanded = (source.id == "xcode" or source.id == "intelligence")
			row.forceExpanded = needle ~= ""
		end
		row.size = (row.status == "partial" and "≥ " or "") .. Model.size(row.bytes)
		if row.status == "skipped" then row.size = "Linked location" elseif row.status == "unsupported" then row.size = "System managed" elseif row.status == "denied" then row.size = "Access restricted" elseif row.status == "stale" then row.size = Model.size(row.bytes) .. " · stale" end
		row.color = source.color or "secondary"
		row.icon = source.icon or "doc"
		row.kept = model.kept[row.id] == true
		return row, matches or row.children and #row.children > 0
	end
	local source = rootId and model.byId[rootId]
	local rows = source and (source.children or {source}) or model.tree
	local result = {}
	for _, row in ipairs(rows) do local value, visible = build(row, false); if visible then result[#result + 1] = value end end
	return result
end
function Model.total(model)
	local bytes = 0; for _, m in pairs(model.measurements) do bytes = bytes + (m.bytes or 0) end
	return bytes
end
function Model.isKept(model, id)
	while id do if model.kept[id] then return true end; id = model.byId[id] and model.byId[id].parentId end
	return false
end
function Model.suggestions(model)
	local result = {}
	for _, row in ipairs(model.leaves) do
		local m = model.measurements[row.id]
		if m and m.bytes and m.bytes > 0 and m.status == "complete" and not Model.isKept(model, row.id) and row.policy ~= "System managed" then
			local value = {}; for k, v in pairs(row) do value[k] = v end
			value.bytes = m.bytes; value.size = Model.size(m.bytes)
			result[#result + 1] = value
		end
	end
	table.sort(result, function(a, b) if (a.action == "trash") ~= (b.action == "trash") then return a.action == "trash" end; return a.bytes > b.bytes end)
	return result
end
function Model.canTrash(model, id)
	local row, m = model.byId[id], model.measurements[id]
	return row and row.action == "trash" and m and m.status == "complete" and (m.bytes or 0) > 0 and not Model.isKept(model, id)
end
-- Capacity is partitioned into measured categories, a visible residual and free space.
-- Shared-block overcounts cannot be truthfully drawn as a partition of capacity.
function Model.distribution(model, disk)
	if not disk or not disk.totalKb or disk.totalKb <= 0 then return {}, "Capacity unavailable" end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	local measured = Model.total(model)
	if measured > total - free then return {}, "Measured allocation exceeds reported usage; shared storage needs reconciliation." end
	local categories, lookup = Model.rows(model), {}
	for _, row in ipairs(categories) do lookup[row.id] = row end
	local segments, assigned = {}, 0
	for _, row in ipairs(categories) do
		local id = row.id
		local bytes = row.bytes or 0; assigned = assigned + bytes
		segments[#segments + 1] = {id = id, name = id == "media" and "Photos" or row.name, color = id == "macos" and "secondary" or row.color,
			bytes = bytes, weight = bytes / total, size = row.size}
	end
	local other = total - free - assigned
	segments[#segments + 1] = {id = "unreconciled", name = "Unreconciled", color = "tertiary", bytes = other, weight = other / total, size = Model.size(other)}
	segments[#segments + 1] = {id = "free", name = "Free", color = "quaternaryLabel", bytes = free, weight = free / total, size = Model.size(free)}
	return segments, "Unreconciled includes inaccessible files, snapshots and filesystem accounting differences. Category measurements may be partial."
end
return Model
