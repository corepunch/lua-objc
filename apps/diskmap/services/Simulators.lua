local SimulatorService = {}

-- Reads the simulator devices of a Mac through the app's service: the device
-- folders, each one's device.plist, and what simctl lists (`listed`). The
-- result is the inventory helpers/Simulators.lua computes over.
local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
local function expand(path, home)
	if path == "~" then return home end
	if type(path) == "string" and path:sub(1, 2) == "~/" then return home .. path:sub(2) end
	return path
end
local function runtimeName(identifier)
	if type(identifier) ~= "string" or identifier == "" or identifier == "unknown" then return "Unknown runtime" end
	local body = identifier:gsub("^com%.apple%.CoreSimulator%.SimRuntime%.", "")
	local product, major, minor = body:match("^(%a+)%-(%d+)%-(%d+)$")
	if product then return product .. " " .. major .. "." .. minor end
	return body:gsub("%-", " ")
end
function SimulatorService.discover(service, home, listed)
	home = home or service.home or "/Users"
	local root = expand("~/Library/Developer/CoreSimulator/Devices", home)
	local children = service.children and service.children(root) or {}
	local devices, names, records = {}, {}, {}
	for runtime, rows in pairs(listed and listed.devices or {}) do
		for _, row in ipairs(rows) do records[row.udid] = {device = row, runtime = runtime} end
	end
	for _, entry in ipairs(children) do
		if type(entry.name) == "string" and entry.name:lower():match(UUID) then
			local info = {name = entry.name, runtime = "unknown"}
			local plist = service.readPropertyList and service.readPropertyList(entry.path .. "/device.plist") or nil
			local named = type(plist) == "table" and type(plist.name) == "string" and plist.name ~= ""
			if named then
				info.name = plist.name
				if type(plist.runtime) == "string" and plist.runtime ~= "" then info.runtime = plist.runtime end
				if type(plist.lastBootedAt) == "string" then info.lastUsedAt = plist.lastBootedAt end
				if type(plist.deviceType) == "string" then info.deviceType = plist.deviceType end
			end
			local known = records[entry.name]
			local record, runtime = known and known.device, known and known.runtime
			if not record and service.simulatorRecord then record, runtime = service.simulatorRecord(entry.name) end
			if record then
				if not named then info.name = record.name or info.name end
				if info.runtime == "unknown" and type(runtime) == "string" then info.runtime = runtime end
				info.lastUsedAt = info.lastUsedAt or record.lastUsedAt
				if type(record.isAvailable) == "boolean" then info.available = record.isAvailable end
				if type(record.state) == "string" then info.state = record.state end
				-- The device type, not the editable name, says what model a device is.
				if type(record.deviceTypeIdentifier) == "string" then info.deviceType = record.deviceTypeIdentifier end
			end
			local key = info.runtime
			names[key] = names[key] or runtimeName(key)
			devices[key] = devices[key] or {}
			table.insert(devices[key], {
				name = info.name, udid = entry.name, state = info.state, isAvailable = info.available,
				lastUsedAt = info.lastUsedAt, deviceType = info.deviceType, dataPath = entry.path .. "/data", dataPathSize = entry.bytes,
				measurePath = entry.path,
			})
		end
	end
	local runtimes = {}
	for identifier, name in pairs(names) do table.insert(runtimes, {identifier = identifier, name = name}) end
	table.sort(runtimes, function(a, b) return a.identifier < b.identifier end)
	return {runtimes = runtimes, devices = devices}
end

return SimulatorService
