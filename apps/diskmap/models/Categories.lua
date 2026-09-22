local Model = require("apps.diskmap.Model")
local Categories = {}
function Categories.rows(model, rootId, query)
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
-- Capacity is partitioned into measured categories, a visible residual and free space.
-- Shared-block overcounts cannot be truthfully drawn as a partition of capacity.
function Categories.distribution(model, disk)
	if not disk or not disk.totalKb or disk.totalKb <= 0 then return {}, "Capacity unavailable" end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	local measured = Model.total(model)
	if measured > total - free then return {}, "Measured allocation exceeds reported usage; shared storage needs reconciliation." end
	local categories = Categories.rows(model)
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
return Categories
