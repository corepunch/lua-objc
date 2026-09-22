local Model = require("apps.diskmap.Model")
local SystemDetails = {}
-- Counts local APFS snapshots in `tmutil listlocalsnapshots /` output.
-- Snapshot lines are stable identity strings; the header line is not one.
function SystemDetails.parseSnapshots(output)
	if type(output) ~= "string" then return nil end
	return #SystemDetails.parseSnapshotDates(output)
end
function SystemDetails.parseSnapshotDates(output)
	if type(output) ~= "string" then return nil end
	local dates = {}
	for line in output:gmatch("[^\n]+") do
		local snapshot = line:match("^(com%.apple%.TimeMachine%.[%d%-]+%.local)$")
		if snapshot then dates[#dates + 1] = snapshot end
	end
	table.sort(dates)
	return dates
end
local function leaves(row, result)
	if row:isLeaf() then result[#result + 1] = row; return end
	for _, child in ipairs(row:getChildren()) do leaves(child, result) end
end
-- Ledger-only breakdown of the System Data group: ranked measured
-- contributors, the group total and virtual-memory allocation when measured.
-- Anything macOS does not expose as files (snapshot exclusive allocation,
-- purgeable space, metadata) cannot appear here by construction.
function SystemDetails.explain(model)
	local group = model.resources:find("system-data")
	local found = {}
	if group then leaves(group, found) end
	local contributors, totalBytes = {}, 0
	for _, row in ipairs(found) do
		local m = model.measurements[row.id]
		if m and m.status == "complete" and (m.bytes or 0) > 0 then
			totalBytes = totalBytes + m.bytes
			contributors[#contributors + 1] = {id = row.id, name = row.name, bytes = m.bytes, size = Model.size(m.bytes)}
		end
	end
	table.sort(contributors, function(a, b) return a.bytes > b.bytes end)
	local measuredLocations = #contributors
	while #contributors > 5 do contributors[#contributors] = nil end
	local vm = model.measurements.vm
	return {
		contributors = contributors,
		measuredLocations = measuredLocations,
		knownLocations = #found,
		total = totalBytes > 0 and {bytes = totalBytes, size = Model.size(totalBytes)} or nil,
		vm = vm and vm.status == "complete" and (vm.bytes or 0) > 0 and {bytes = vm.bytes, size = Model.size(vm.bytes)} or nil,
	}
end
function SystemDetails.format(explanation, snapshots)
	local lines = {}
	if explanation.total then
		lines[#lines + 1] = "Measured System Data allocation is " .. explanation.total.size .. " across " .. explanation.measuredLocations .. " of " .. explanation.knownLocations .. " known locations."
	else
		lines[#lines + 1] = "System Data is still being measured across " .. explanation.knownLocations .. " known locations."
	end
	for _, contributor in ipairs(explanation.contributors) do
		lines[#lines + 1] = "· " .. contributor.name .. " — " .. contributor.size
	end
	if explanation.vm then lines[#lines + 1] = "· Virtual memory (swap) — " .. explanation.vm.size end
	if snapshots ~= nil then
		lines[#lines + 1] = snapshots == 0 and "No local Time Machine snapshots are currently held." or
			(tostring(snapshots) .. " local Time Machine snapshot" .. (snapshots == 1 and " is" or "s are") .. " currently held; macOS manages their lifetime and file scans cannot attribute their exclusive allocation.")
	else
		lines[#lines + 1] = "Local snapshots are system managed; file scans cannot attribute their exclusive allocation."
	end
	return table.concat(lines, "\n")
end
return SystemDetails
