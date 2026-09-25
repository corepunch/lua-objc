local Model = require("apps.diskmap.Model")
local Categories = {}
local function projection(source)
	return {id = source.id, name = source.name, subtitle = source.subtitle, path = source.path, policy = source.policy,
		action = source.action, consequence = source.consequence, settingsSection = source.settingsSection,
		reviewThreshold = source.reviewThreshold, agent = source.agent, icon = source.icon, color = source.color, appIcon = source.appIcon, fileIcon = source.fileIcon}
end
function Categories.rows(model, rootId, query)
	local needle = (query or ""):lower()
	local function build(source, inheritedMatch)
		local row = projection(source)
		local matches = inheritedMatch or (source.name .. " " .. source.subtitle .. " " .. (source.path or "")):lower():find(needle, 1, true) ~= nil
		local m = model.measurements[source.id] or {}
		row.bytes, row.status = m.bytes, m.status or "notMeasured"
		if not source:isLeaf() then
			row.children = {}; local total, measured, complete, attempted, calculating, failed, excluded = 0, false, true, false, false, false, true
			for _, child in ipairs(source:getChildren()) do
				local value, visible = build(child, matches)
				if value.bytes then total = total + value.bytes; measured = true end
				if value.status ~= "excluded" then excluded = false end
				if value.status == "failed" then failed = true end
				if value.status == "calculating" then calculating = true end
				if value.status ~= "complete" then complete = false end
				if value.status ~= "notMeasured" then attempted = true end
				if visible then table.insert(row.children, value) end
			end
			row.bytes = measured and total or nil
			row.status = excluded and "excluded" or calculating and "calculating" or complete and "complete" or measured and "partial" or failed and "failed" or attempted and "denied" or "notMeasured"
			row.expanded = (source.id == "xcode" or source.id == "intelligence")
			row.forceExpanded = needle ~= ""
		end
		row.size = (row.status == "partial" and "≥ " or "") .. Model.size(row.bytes)
		if row.status == "excluded" then row.size = "Not scanned" elseif row.status == "skipped" then row.size = "Linked location" elseif row.status == "unsupported" then row.size = "System managed" elseif row.status == "denied" then row.size = "Access restricted" elseif row.status == "failed" then row.size = "Unavailable" end
		row.calculating = row.status == "calculating"
		if row.calculating then row.size = "Calculating…" end
		row.color = source.color or "secondary"
		row.icon = source.icon or "doc"
		row.kept = model.kept[row.id] == true
		return row, matches or row.children and #row.children > 0
	end
	local source = rootId and model.resources:find(rootId)
	local rows = source and (source:isLeaf() and {source} or source:getChildren()) or model.resources:roots()
	local result = {}
	for _, row in ipairs(rows) do local value, visible = build(row, false); if visible then table.insert(result, value) end end
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
		table.insert(segments, {id = id, name = id == "media" and "Photos" or row.name, color = id == "macos" and "secondary" or row.color,
			bytes = bytes, weight = bytes / total, size = row.size})
	end
	table.sort(segments, function(left, right)
		if left.bytes ~= right.bytes then return left.bytes > right.bytes end
		return left.id < right.id
	end)
	local other = total - free - assigned
	table.insert(segments, {id = "unreconciled", name = "Not attributed", color = "tertiary", bytes = other, weight = other / total, size = Model.size(other)})
	table.insert(segments, {id = "free", name = "Free", color = "quaternaryLabel", bytes = free, weight = free / total, size = Model.size(free)})
	return segments, "Not attributed can include inaccessible files, snapshots and filesystem accounting differences. Category measurements may be partial."
end
-- Flat management rows retain their owner and exact path; totals stay in the ledger.
function Categories.managementRows(model, rootId, query, filter)
	local result, needle = {}, (query or ""):lower()
	local function visit(row, owner)
		if not row:isLeaf() then
			for _, child in ipairs(row:getChildren()) do visit(child, row.name) end
		else
			local m = model.measurements[row.id] or {}
			local impact = row.policy == "Essential" and "Essential to keep" or row.policy == "Rebuildable" and "Safe/rebuildable" or "Needs review"
			if (not filter or filter == "All" or filter == impact) and (row.name .. " " .. (owner or "") .. " " .. (row.path or "")):lower():find(needle, 1, true) then
				table.insert(result, {id = row.id, name = row.name, subtitle = owner, path = row.path or "System managed", icon = row.icon, color = row.color, appIcon = row.appIcon, fileIcon = row.fileIcon, impact = impact,
					size = m.status == "excluded" and "Not scanned" or m.status == "calculating" and "Calculating…" or m.status == "denied" and "Access restricted" or (m.status == "partial" and "≥ " or "") .. Model.size(m.bytes),
					bytes = m.bytes, partial = m.status == "partial", calculating = m.status == "calculating"})
			end
		end
	end
	if rootId and model.resources:find(rootId) then visit(model.resources:find(rootId)) else for _, row in ipairs(model.resources:roots()) do visit(row) end end
	return result
end
return Categories
