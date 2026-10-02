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
		if snapshot then table.insert(dates, snapshot) end
	end
	table.sort(dates)
	return dates
end
function SystemDetails.format(explanation, snapshots)
	local lines = {}
	if explanation.total then
		table.insert(lines, "Measured System Data allocation is " .. explanation.total.size .. " across " .. explanation.measuredLocations .. " of " .. explanation.knownLocations .. " known locations.")
	else
		table.insert(lines, "System Data is still being measured across " .. explanation.knownLocations .. " known locations.")
	end
	for _, contributor in ipairs(explanation.contributors) do
		table.insert(lines, "· " .. contributor.name .. " — " .. contributor.size)
	end
	if explanation.vm then table.insert(lines, "· Virtual memory (swap) — " .. explanation.vm.size) end
	if snapshots ~= nil then
		table.insert(lines, snapshots == 0 and "No local Time Machine snapshots are currently held." or
			(tostring(snapshots) .. " local Time Machine snapshot" .. (snapshots == 1 and " is" or "s are") .. " currently held; macOS manages their lifetime and file scans cannot attribute their exclusive allocation."))
	else
		table.insert(lines, "Local snapshots are system managed; file scans cannot attribute their exclusive allocation.")
	end
	return table.concat(lines, "\n")
end
return SystemDetails
