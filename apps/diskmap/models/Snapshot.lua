local Model = require("apps.diskmap.Model")
local Snapshot = {}

-- A saved Mock HDD snapshot doubles as the previous state of this Mac: its
-- files are measured once with the same catalog as a live scan, and the
-- per-location totals are kept (a few kilobytes) so later scans compare
-- without decoding the snapshot again. Changes smaller than `minimumChange`
-- are ordinary churn — caches, logs — and are not reported.
Snapshot.minimumChange = 50e6
Snapshot.headerSize = 72
Snapshot.overviewLimit = 4

local function little64(bytes, offset)
	local value = 0
	for index = 7, 0, -1 do value = value * 256 + bytes:byte(offset + index) end
	return value
end

-- The snapshot's creation time, read from its uncompressed header, or nil
-- when the file is missing or not a snapshot.
function Snapshot.created(path)
	local file = path and io.open(path, "rb")
	if not file then return nil end
	local header = file:read(Snapshot.headerSize)
	file:close()
	if not header or #header < Snapshot.headerSize or header:sub(1, 8) ~= "DMOCK002" then return nil end
	local created = little64(header, 57)
	return created > 0 and created or nil
end

-- Measured bytes per catalog location. Denied, excluded and unmeasured
-- locations are left out, so they never read as growth or shrinkage.
function Snapshot.totals(model)
	local totals = {}
	for _, row in ipairs(model.resources:leaves()) do
		local m = model.measurements[row.id]
		if m and (m.status == "complete" or m.status == "partial") and m.bytes then totals[row.id] = m.bytes end
	end
	return totals
end

-- One line with the creation time, then one `id bytes` line per location.
function Snapshot.encode(baseline)
	local lines = {"created " .. string.format("%d", baseline.createdAt or 0)}
	local ids = {}
	for id in pairs(baseline.totals or {}) do table.insert(ids, id) end
	table.sort(ids)
	for _, id in ipairs(ids) do table.insert(lines, id .. " " .. string.format("%d", baseline.totals[id])) end
	return table.concat(lines, "\n") .. "\n"
end

function Snapshot.decode(text)
	if type(text) ~= "string" then return nil end
	local created = text:match("^created (%d+)\n")
	if not created then return nil end
	local totals = {}
	for id, bytes in text:gmatch("\n([^%s]+) (%d+)") do totals[id] = tonumber(bytes) end
	return {createdAt = tonumber(created), totals = totals}
end

local function ancestry(row)
	local names, parent = {}, row:getParent()
	while parent do
		table.insert(names, 1, parent.name)
		parent = parent:getParent()
	end
	return table.concat(names, " › ")
end

local function since(createdAt)
	return (os.date("%b %e", createdAt):gsub("  ", " "))
end

-- Locations that grew or shrank since the snapshot, largest change first,
-- with totals for the section summary. Locations measured on only one side
-- are skipped: a new tool or a newly denied folder is not a change in size.
function Snapshot.changes(model, baseline)
	if not baseline or not baseline.totals then return nil end
	local now = Snapshot.totals(model)
	local rows, grew, freed = {}, 0, 0
	for id, after in pairs(now) do
		local before = baseline.totals[id]
		local resource = model.resources:find(id)
		if before and resource and math.abs(after - before) >= Snapshot.minimumChange then
			local delta = after - before
			if delta > 0 then grew = grew + delta else freed = freed - delta end
			table.insert(rows, {id = id, name = resource.name, subtitle = ancestry(resource), icon = resource.icon, color = resource.color,
				appIcon = resource.appIcon, path = resource.path, delta = delta, bytes = after, size = Model.size(after),
				before = Model.size(before), grew = delta > 0,
				text = (delta > 0 and "+" or "−") .. Model.size(math.abs(delta))})
		end
	end
	table.sort(rows, function(a, b)
		if math.abs(a.delta) ~= math.abs(b.delta) then return math.abs(a.delta) > math.abs(b.delta) end
		return a.id < b.id
	end)
	local largest = rows[1] and math.abs(rows[1].delta) or 0
	for _, row in ipairs(rows) do
		row.relative = largest > 0 and math.abs(row.delta) / largest or 0
		row.detail, row.shareText = row.text, ""
		row.levelColor = row.grew and "systemOrange" or "systemGreen"
	end
	local date = baseline.createdAt and since(baseline.createdAt) or "the snapshot"
	local parts = {}
	if grew > 0 then table.insert(parts, Model.size(grew) .. " more") end
	if freed > 0 then table.insert(parts, Model.size(freed) .. " freed") end
	return {rows = rows, since = date, grew = grew, freed = freed,
		title = "Changes Since " .. date,
		detail = #rows == 0 and ("No location changed by more than " .. Model.size(Snapshot.minimumChange) .. " since the " .. date .. " snapshot.")
			or (Model.plural(#rows, "location") .. " changed since the " .. date .. " snapshot · " .. table.concat(parts, ", "))}
end

-- The first rows for the overview tiles, sharing the section's summary.
function Snapshot.overview(changes)
	if not changes or #changes.rows == 0 then return nil end
	local rows = {}
	for index = 1, math.min(Snapshot.overviewLimit, #changes.rows) do table.insert(rows, changes.rows[index]) end
	return {rows = rows, detail = changes.detail, since = "the " .. changes.since .. " snapshot", all = #changes.rows > #rows}
end

return Snapshot
