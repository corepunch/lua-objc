local Model = require("apps.diskmap.Model")
local Simulators = {}
function Simulators.rows(inventory, query, filter)
	local rows, runtimes, needle = {}, {}, (query or ""):lower()
	for _, runtime in ipairs(inventory.runtimes or {}) do runtimes[runtime.identifier] = runtime.name end
	for runtime, devices in pairs(inventory.devices or {}) do
		for _, device in ipairs(devices) do
			local name = device.name or "Unnamed device"
			local runtimeName = runtimes[runtime] or runtime:gsub("com.apple.CoreSimulator.SimRuntime.", ""):gsub("%-", " ")
			local available = device.isAvailable == true
			if (filter ~= "Unavailable" or not available) and (name .. " " .. runtimeName .. " " .. (device.udid or "")):lower():find(needle, 1, true) then
				rows[#rows + 1] = {id = device.udid, name = name, runtime = runtimeName,
					state = available and (device.state or "Unknown") or "Unavailable",
					available = available, running = device.state ~= "Shutdown", path = device.dataPath,
					bytes = device.dataPathSize, size = Model.size(device.dataPathSize),
					lastUse = device.lastUsedAt and device.lastUsedAt:gsub("T", " "):gsub("Z$", " UTC") or "Not recorded"}
			end
		end
	end
	table.sort(rows, function(a, b) if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end; return (a.id or "") < (b.id or "") end)
	return rows
end
function Simulators.command(action, row)
	if not row or row.running or type(row.id) ~= "string" or not row.id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return nil end
	if action ~= "erase" and action ~= "delete" then return nil end
	if action == "erase" and not row.available then return nil end
	return {"/usr/bin/xcrun", "simctl", action, row.id}
end
function Simulators.impact(action, row)
	return (action == "erase" and "Erase contents of " or "Delete ") .. row.name .. "?\n" .. row.runtime .. " · " .. row.id .. "\n\nPermanently removes installed test apps, accounts and device data (" .. row.size .. "). " ..
		(action == "delete" and "The device is also removed. " or "The device remains available. ") .. "Installed runtimes are preserved. This cannot be undone."
end
return Simulators
