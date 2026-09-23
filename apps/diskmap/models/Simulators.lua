local Model = require("apps.diskmap.Model")
local Simulators = {}
local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
function Simulators.rows(inventory, query, filter)
	local rows, runtimes, needle = {}, {}, (query or ""):lower()
	for _, runtime in ipairs(inventory.runtimes or {}) do runtimes[runtime.identifier] = runtime.name end
	for runtime, devices in pairs(inventory.devices or {}) do
		for _, device in ipairs(devices) do
			local name = device.name or "Unnamed device"
			local runtimeName = runtimes[runtime] or runtime:gsub("com.apple.CoreSimulator.SimRuntime.", ""):gsub("%-", " ")
			local available = device.isAvailable == true
			if (filter ~= "Unavailable" or not available) and (name .. " " .. runtimeName .. " " .. (device.udid or "")):lower():find(needle, 1, true) then
				table.insert(rows, {id = device.udid, name = name, runtime = runtimeName,
					state = available and (device.state or "Unknown") or "Unavailable",
					available = available, running = device.state ~= "Shutdown", path = device.dataPath,
					bytes = device.dataPathSize, size = Model.size(device.dataPathSize),
					lastUse = device.lastUsedAt and device.lastUsedAt:gsub("T", " "):gsub("Z$", " UTC") or "Not recorded"})
			end
		end
	end
	table.sort(rows, function(a, b) if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end; return (a.id or "") < (b.id or "") end)
	return rows
end
function Simulators.validate(action, row, model)
	if action ~= "erase" and action ~= "delete" then return false, {code = "unsupported_action", message = "Simulator action is not supported."} end
	if not row then return false, {code = "missing_device", message = "No simulator device is selected."} end
	if type(row.id) ~= "string" or not row.id:match(UUID) then return false, {code = "invalid_uuid", message = "Simulator identifier is not a UUID."} end
	if row.running then return false, {code = "device_running", message = "Shut down the simulator before changing it."} end
	if action == "erase" and not row.available then return false, {code = "device_unavailable", message = "Unavailable simulators cannot be erased."} end
	if model then
		local catalog = model.resources:find("simulators")
		if catalog and catalog:isKept() then return false, {code = "kept_resource", message = "Keep protects simulator storage."} end
	end
	return true
end
function Simulators.command(action, row, model)
	local ok, err = Simulators.validate(action, row, model)
	if not ok then return nil, err end
	return {"/usr/bin/xcrun", "simctl", action, row.id}
end
function Simulators.impact(action, row)
	return (action == "erase" and "Erase contents of " or "Delete ") .. row.name .. "?\n" .. row.runtime .. " · " .. row.id .. "\n\nPermanently removes installed test apps, accounts and device data (" .. row.size .. "). " ..
		(action == "delete" and "The device is also removed. " or "The device remains available. ") .. "Installed runtimes are preserved. This cannot be undone."
end
return Simulators
