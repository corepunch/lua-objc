local Snapshot = {}

-- A saved Mock HDD snapshot doubles as the previous state of this Mac: its
-- files are measured once with the same catalog as a live scan, and the
-- per-location totals are kept (a few kilobytes) so later scans compare
-- without decoding the snapshot again. Changes smaller than `minimumChange`
-- are ordinary churn — caches, logs — and are not reported.
Snapshot.minimumChange = 50e6
Snapshot.overviewLimit = 4

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

-- The first rows for the overview tiles, sharing the section's summary.
function Snapshot.overview(changes)
	if not changes or #changes.rows == 0 then return nil end
	local rows = {}
	for index = 1, math.min(Snapshot.overviewLimit, #changes.rows) do table.insert(rows, changes.rows[index]) end
	return {rows = rows, detail = changes.detail, since = "the " .. changes.since .. " snapshot", all = #changes.rows > #rows}
end

return Snapshot
