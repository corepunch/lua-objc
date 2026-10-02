local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")
local Store = require("apps.diskmap.Store")
local Categories = {}
local function projection(source)
	return {id = source.id, name = source.name, subtitle = source.subtitle, path = source.path, policy = source.policy,
		action = source.action, consequence = source.consequence, settingsSection = source.settingsSection,
		reviewThreshold = source.reviewThreshold, agent = source.agent, icon = source.icon, color = source.color, appIcon = source.appIcon, fileIcon = source.fileIcon}
end
function Categories.rows(rootId, query)
	local model = Model.db
	local needle = (query or ""):lower()
	local function build(source, inheritedMatch)
		local row = projection(source)
		local matches = inheritedMatch or (source.name .. " " .. source.subtitle .. " " .. (source.path or "")):lower():find(needle, 1, true) ~= nil
		local m = model.measurements[source.id] or {}
		row.bytes, row.status = m.bytes, m.status or "notMeasured"
		if not source:isLeaf() then
			row.children = {}; local total, measured, complete, attempted, calculating, failed, excluded, unsupported, protected = 0, false, true, false, false, false, true, true, true
			local denied = false
			for _, child in ipairs(source:children()) do
				local value, visible = build(child, matches)
				if value.status == "denied" then denied = true end
				if value.bytes then total = total + value.bytes; measured = true end
				if value.status ~= "excluded" then excluded = false end
				if value.status ~= "unsupported" then unsupported = false end
				if value.status ~= "protected" then protected = false end
				if value.status == "failed" then failed = true end
				if value.status == "calculating" then calculating = true end
				if value.status ~= "complete" then complete = false end
				if value.status ~= "notMeasured" then attempted = true end
				if visible then table.insert(row.children, value) end
			end
			row.bytes = measured and total or nil
			-- A group whose readable locations are empty and whose others
			-- could not be read has no access, not "≥ 0 KB".
			if denied and total == 0 and not calculating then row.bytes, measured, complete = nil, false, false end
			-- A group of only system-managed resources (Backups holds just local
			-- snapshots) is system managed, not restricted: nothing was denied.
			-- A group macOS keeps entirely from every app is protected; with
			-- readable siblings its total is a lower bound, like any partial one.
			row.status = excluded and "excluded" or unsupported and "unsupported" or protected and "protected" or calculating and "calculating" or complete and "complete" or measured and "partial" or failed and "failed" or attempted and "denied" or "notMeasured"
			row.expanded = (source.id == "xcode" or source.id == "intelligence")
			row.forceExpanded = needle ~= ""
		end
		Format.sizeLabel(row, row.status, row.bytes)
		row.color = source.color or "secondary"
		row.icon = source.icon or "doc"
		row.kept = model.kept[row.id] == true
		return row, matches or row.children and #row.children > 0
	end
	local source = rootId and Locations:find(rootId)
	local rows = source and (source:isLeaf() and {source} or source:children()) or Locations:roots()
	local result = {}
	for _, row in ipairs(rows) do local value, visible = build(row, false); if visible then table.insert(result, value) end end
	return result
end
-- One rolled-up row (leaf or group) by id, with the same status and size text
-- the category lists show.
function Categories.row(id)
	local model = Model.db
	local resource = Locations:find(id)
	if not resource then return nil end
	local parent = resource:parent()
	for _, row in ipairs(Categories.rows(parent and parent.id or nil)) do
		if row.id == id then return row end
	end
end
-- How much of the disk the categories account for, under the category list.
function Categories.coverage(disk)
	local model = Model.db
	local measured = Store.total(model)
	local partial = (model.scan.errors or 0) > 0
	local text = (partial and "At least " or "") .. Format.size(measured) .. " measured"
	if partial then text = text .. string.format(" · %d filesystem read issues", model.scan.errors) end
	if model.scan.running then
		text = text .. " so far · scan in progress"
	elseif disk then
		local difference = (disk.totalKb - disk.freeKb) * 1024 - measured
		text = text .. " · " .. (difference < 0 and "−" or "") .. Format.size(math.abs(difference)) .. " not attributed"
	end
	return text
end
-- Capacity is partitioned into measured categories, a visible residual and free space.
-- Shared-block overcounts cannot be truthfully drawn as a partition of capacity.
function Categories.distribution(disk)
	local model = Model.db
	if not disk or not disk.totalKb or disk.totalKb <= 0 then return {}, "Capacity unavailable" end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	local measured = Store.total(model)
	if measured > total - free then return {}, "Measured allocation exceeds reported usage; shared storage needs reconciliation." end
	local categories = Categories.rows()
	local segments, assigned = {}, 0
	for _, row in ipairs(categories) do
		local id = row.id
		local bytes = row.bytes or 0; assigned = assigned + bytes
		table.insert(segments, {id = id, name = row.name, color = id == "macos" and "secondary" or row.color,
			bytes = bytes, weight = bytes / total, size = row.size})
	end
	table.sort(segments, function(left, right)
		if left.bytes ~= right.bytes then return left.bytes > right.bytes end
		return left.id < right.id
	end)
	local other = total - free - assigned
	table.insert(segments, {id = "unreconciled", name = model.scan.running and "Not measured yet" or "Not attributed", color = "tertiary", bytes = other, weight = other / total, size = Format.size(other)})
	table.insert(segments, {id = "free", name = "Free", color = "quaternaryLabel", bytes = free, weight = free / total, size = Format.size(free)})
	if model.scan.running then return segments, "Measurements are still arriving. The gray part includes storage Diskmap has not measured yet; it is not a cleanup estimate." end
	return segments, "Not attributed can include inaccessible files, snapshots and filesystem accounting differences. Category measurements may be partial."
end
-- Flat management rows retain their owner and exact path; totals stay in the ledger.
function Categories.managementRows(rootId, query, filter)
	local model = Model.db
	local result, needle = {}, (query or ""):lower()
	local function visit(row, owner)
		if not row:isLeaf() then
			for _, child in ipairs(row:children()) do visit(child, row.name) end
		else
			local m = model.measurements[row.id] or {}
			local impact = row.policy == "Essential" and "Essential to keep" or row.policy == "Rebuildable" and "Safe/rebuildable" or "Needs review"
			if (not filter or filter == "All" or filter == impact) and (row.name .. " " .. (owner or "") .. " " .. (row.path or "")):lower():find(needle, 1, true) then
				table.insert(result, {id = row.id, name = row.name, subtitle = owner, path = row.path or "System managed", icon = row.icon, color = row.color, appIcon = row.appIcon, fileIcon = row.fileIcon, info = Locations:opensElsewhere(row.id), impact = impact,
					bytes = m.bytes})
				Format.sizeLabel(result[#result], m.status, m.bytes)
			end
		end
	end
	if rootId and Locations:find(rootId) then visit(Locations:find(rootId)) else for _, row in ipairs(Locations:roots()) do visit(row) end end
	return result
end
return Categories
