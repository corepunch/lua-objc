local Model = require("apps.diskmap.Model")
local Simulators = {}
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
function Simulators.discover(service, home)
	home = home or service.home or "/Users"
	local root = expand("~/Library/Developer/CoreSimulator/Devices", home)
	local children = service.children and service.children(root) or {}
	local devices, names = {}, {}
	for _, entry in ipairs(children) do
		if type(entry.name) == "string" and entry.name:lower():match(UUID) then
			local info = {name = entry.name, runtime = "unknown", available = true, state = "Not recorded"}
			local plist = service.readPropertyList and service.readPropertyList(entry.path .. "/device.plist") or nil
			local named = type(plist) == "table" and type(plist.name) == "string" and plist.name ~= ""
			if named then
				info.name = plist.name
				if type(plist.runtime) == "string" and plist.runtime ~= "" then info.runtime = plist.runtime end
				if type(plist.lastBootedAt) == "string" then info.lastUsedAt = plist.lastBootedAt end
			end
			local record, runtime = nil, nil
			if service.simulatorRecord then record, runtime = service.simulatorRecord(entry.name) end
			if record then
				if not named then info.name = record.name or info.name end
				if info.runtime == "unknown" and type(runtime) == "string" then info.runtime = runtime end
				info.lastUsedAt = info.lastUsedAt or record.lastUsedAt
				info.available = record.isAvailable ~= false
				if type(record.state) == "string" then info.state = record.state end
			end
			local key = info.runtime
			names[key] = names[key] or runtimeName(key)
			devices[key] = devices[key] or {}
			table.insert(devices[key], {
				name = info.name, udid = entry.name, state = info.state, isAvailable = info.available ~= false,
				lastUsedAt = info.lastUsedAt, dataPath = entry.path .. "/data", dataPathSize = entry.bytes,
				measurePath = entry.path,
			})
		end
	end
	local runtimes = {}
	for identifier, name in pairs(names) do table.insert(runtimes, {identifier = identifier, name = name}) end
	table.sort(runtimes, function(a, b) return a.identifier < b.identifier end)
	return {runtimes = runtimes, devices = devices}
end
-- Devices unused for this long are worth a look; the threshold is a review
-- hint, never a deletion rule, and devices without a recorded use never match.
Simulators.staleDays = 90
Simulators.filters = {"All", "Unavailable", "Unused for 90 days"}

-- Days since an ISO 8601 timestamp ("2026-09-20T16:20:00Z"), or nil when the
-- date is missing or unreadable.
function Simulators.age(timestamp, now)
	if type(timestamp) ~= "string" then return nil end
	local year, month, day = timestamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if not year then return nil end
	local then_ = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12})
	return math.max(0, math.floor(((now or os.time()) - then_) / 86400))
end

function Simulators.rows(inventory, query, filter, now)
	local rows, runtimes, needle = {}, {}, (query or ""):lower()
	for _, runtime in ipairs(inventory.runtimes or {}) do runtimes[runtime.identifier] = runtime.name end
	for runtime, devices in pairs(inventory.devices or {}) do
		for _, device in ipairs(devices) do
			local name = device.name or "Unnamed device"
			local runtimeName = runtimes[runtime] or runtime:gsub("com.apple.CoreSimulator.SimRuntime.", ""):gsub("%-", " ")
			local available = device.isAvailable == true
			local age = Simulators.age(device.lastUsedAt, now)
			local matchesFilter = (filter ~= "Unavailable" or not available)
				and (filter ~= Simulators.filters[3] or (age ~= nil and age >= Simulators.staleDays))
			if matchesFilter and (name .. " " .. runtimeName .. " " .. (device.udid or "")):lower():find(needle, 1, true) then
				table.insert(rows, {id = device.udid, name = name, runtime = runtimeName,
					state = available and (device.state or "Unknown") or "Unavailable",
					available = available, running = device.state == "Booted" or device.state == "Booting" or device.state == "Shutting Down", path = device.dataPath,
					bytes = device.dataPathSize, size = Model.size(device.dataPathSize), age = age,
					runtimeIdentifier = runtime,
					lastUse = device.lastUsedAt and device.lastUsedAt:gsub("T", " "):gsub("Z$", " UTC") or "Not recorded"})
			end
		end
	end
	table.sort(rows, function(a, b) if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end; return (a.id or "") < (b.id or "") end)
	return rows
end
local PLATFORMS = {
	["com.apple.platform.iphonesimulator"] = "iOS", ["com.apple.platform.appletvsimulator"] = "tvOS",
	["com.apple.platform.watchsimulator"] = "watchOS", ["com.apple.platform.xrsimulator"] = "visionOS",
}

-- Installed runtimes from `xcrun simctl runtime list -j`: an object keyed by
-- runtime image UUID. Unknown fields stay unknown; sizes are never invented.
-- Device counts come from the device inventory's runtime identifiers.
function Simulators.runtimeRows(list, inventory, query)
	local rows, needle = {}, (query or ""):lower()
	local counts = {}
	for runtime, devices in pairs(inventory and inventory.devices or {}) do counts[runtime] = #devices end
	for key, entry in pairs(type(list) == "table" and list or {}) do
		if type(entry) == "table" then
			local id = type(entry.identifier) == "string" and entry.identifier or tostring(key)
			local platform = PLATFORMS[entry.platformIdentifier]
				or (type(entry.runtimeIdentifier) == "string" and entry.runtimeIdentifier:match("SimRuntime%.(%a+)%-")) or "Simulator"
			local version = type(entry.version) == "string" and entry.version or "?"
			local name = platform .. " " .. version
			local build = type(entry.build) == "string" and entry.build or nil
			local bytes = tonumber(entry.sizeBytes)
			local devices = counts[entry.runtimeIdentifier] or 0
			if (name .. " " .. (build or "") .. " " .. id):lower():find(needle, 1, true) then
				table.insert(rows, {id = id, name = name, subtitle = table.concat({build and ("Build " .. build) or nil,
					type(entry.kind) == "string" and entry.kind or nil, type(entry.state) == "string" and entry.state or nil}, " · "),
					platform = platform, version = version, runtimeIdentifier = entry.runtimeIdentifier,
					bytes = bytes, size = Model.size(bytes), deletable = entry.deletable == true,
					devices = devices, deviceText = devices == 0 and "No devices" or (devices .. (devices == 1 and " device" or " devices")),
					lastUse = type(entry.lastUsedAt) == "string" and entry.lastUsedAt:sub(1, 10) or "Not recorded",
					path = type(entry.path) == "string" and entry.path or nil})
			end
		end
	end
	table.sort(rows, function(a, b)
		if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
		return a.id < b.id
	end)
	return rows
end

-- Totals for the page header. Unmeasured devices and runtimes add no bytes.
function Simulators.summary(inventory, runtimes, now)
	local result = {devices = 0, deviceBytes = 0, unavailable = 0, unavailableBytes = 0, stale = 0, staleBytes = 0,
		runtimes = #(runtimes or {}), runtimeBytes = 0}
	for _, row in ipairs(Simulators.rows(inventory or {}, nil, nil, now)) do
		result.devices = result.devices + 1
		result.deviceBytes = result.deviceBytes + (row.bytes or 0)
		if not row.available then
			result.unavailable = result.unavailable + 1
			result.unavailableBytes = result.unavailableBytes + (row.bytes or 0)
		end
		if row.age and row.age >= Simulators.staleDays then
			result.stale = result.stale + 1
			result.staleBytes = result.staleBytes + (row.bytes or 0)
		end
	end
	for _, row in ipairs(runtimes or {}) do result.runtimeBytes = result.runtimeBytes + (row.bytes or 0) end
	return result
end

-- Deleting a runtime removes an operating system image. Only images simctl
-- reports as deletable qualify; Keep on runtimes protects every image, and
-- devices on the runtime become unavailable (their data remains).
function Simulators.validateRuntime(row, model)
	if not row then return false, {code = "missing_runtime", message = "No runtime is selected."} end
	if type(row.id) ~= "string" or not row.id:match(UUID) then return false, {code = "invalid_uuid", message = "Runtime identifier is not a UUID."} end
	if row.deletable ~= true then return false, {code = "not_deletable", message = "simctl reports this runtime as not deletable; manage it in Xcode."} end
	if model then
		local catalog = model.resources:find("runtimes")
		if catalog and catalog:isKept() then return false, {code = "kept_resource", message = "Keep protects simulator runtimes."} end
	end
	return true
end
function Simulators.runtimeCommand(row, model)
	local ok, err = Simulators.validateRuntime(row, model)
	if not ok then return nil, err end
	return {"/usr/bin/xcrun", "simctl", "runtime", "delete", row.id}
end
function Simulators.runtimeImpact(row)
	return "Delete " .. row.name .. "?\n" .. row.id .. "\n\nRemoves this simulator operating system (" .. row.size .. "). "
		.. (row.devices > 0 and (row.deviceText .. " using it will become unavailable; their data stays until you delete them. ") or "")
		.. "Xcode can download it again from Settings › Components."
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
