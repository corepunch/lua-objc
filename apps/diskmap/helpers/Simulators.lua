local Format = require("apps.diskmap.helpers.Format")
local Simulators = {}
local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
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

-- The SF Symbol for a device or runtime name: lists have no column headers,
-- so the symbol says what kind of device a row is.
local SYMBOLS = {{"ipad", "ipad"}, {"watch", "applewatch"}, {"tv", "appletv"}, {"vision", "vision.pro"}, {"xr", "vision.pro"}}
function Simulators.symbol(name)
	local lowered = (name or ""):lower()
	for _, entry in ipairs(SYMBOLS) do
		if lowered:find(entry[1], 1, true) then return entry[2] end
	end
	return "iphone"
end

function Simulators.rows(inventory, query, filter, now)
	local rows, runtimes, needle = {}, {}, (query or ""):lower()
	for _, runtime in ipairs(inventory.runtimes or {}) do runtimes[runtime.identifier] = runtime.name end
	for runtime, devices in pairs(inventory.devices or {}) do
		for _, device in ipairs(devices) do
			local name = device.name or "Unnamed device"
			local runtimeName = runtimes[runtime] or runtime:gsub("com.apple.CoreSimulator.SimRuntime.", ""):gsub("%-", " ")
			local available = device.isAvailable
			local running
			if device.state == "Shutdown" then running = false
			elseif device.state == "Booted" or device.state == "Booting" or device.state == "Shutting Down" then running = true end
			local age = Simulators.age(device.lastUsedAt, now)
			local matchesFilter = (filter ~= "Unavailable" or available == false)
				and (filter ~= Simulators.filters[3] or (age ~= nil and age >= Simulators.staleDays))
			if matchesFilter and (name .. " " .. runtimeName .. " " .. (device.udid or "")):lower():find(needle, 1, true) then
				-- A value names itself or stays empty: a dash in a list without
				-- headers says nothing.
				table.insert(rows, {id = device.udid, name = name, runtime = runtimeName,
					icon = Simulators.symbol(name .. " " .. runtimeName), color = available == false and "systemOrange" or "systemBlue",
					state = available == false and "Unavailable" or (device.state or "State unknown"),
					available = available, running = running, path = device.dataPath,
					bytes = device.dataPathSize, size = Format.size(device.dataPathSize), age = age,
					runtimeIdentifier = runtime, deviceType = device.deviceType,
					lastUse = age and Format.used(Format.ago(age)) or "Last use unknown"})
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
function Simulators.runtimeRows(list, inventory, query, now)
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
			local age = Simulators.age(entry.lastUsedAt, now)
			local build = type(entry.build) == "string" and entry.build or nil
			local bytes = tonumber(entry.sizeBytes)
			local devices = counts[entry.runtimeIdentifier] or 0
			if (name .. " " .. (build or "") .. " " .. id):lower():find(needle, 1, true) then
				table.insert(rows, {id = id, name = name, icon = Simulators.symbol(platform), color = "systemIndigo", subtitle = table.concat({build and ("Build " .. build) or nil,
					type(entry.kind) == "string" and entry.kind or nil, type(entry.state) == "string" and entry.state or nil}, " · "),
					platform = platform, version = version, runtimeIdentifier = entry.runtimeIdentifier,
					bytes = bytes, size = Format.size(bytes), deletable = entry.deletable == true,
					devices = devices, deviceText = devices == 0 and "No devices" or Format.plural(devices, "device"),
					lastUse = age and Format.used(Format.ago(age)) or "Last use unknown",
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
		runtimes = #(runtimes or {}), runtimeBytes = 0, unknownAvailability = 0}
	for _, row in ipairs(Simulators.rows(inventory or {}, nil, nil, now)) do
		result.devices = result.devices + 1
		result.deviceBytes = result.deviceBytes + (row.bytes or 0)
		if row.available == nil then result.unknownAvailability = result.unknownAvailability + 1 end
		if row.available == false then
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
function Simulators.validateRuntime(row, kept)
	if not row then return false, {code = "missing_runtime", message = "No runtime is selected."} end
	if type(row.id) ~= "string" or not row.id:match(UUID) then return false, {code = "invalid_uuid", message = "Runtime identifier is not a UUID."} end
	if row.deletable ~= true then return false, {code = "not_deletable", message = "simctl reports this runtime as not deletable; manage it in Xcode."} end
	if kept and kept("runtimes") then return false, {code = "kept_resource", message = "Keep protects simulator runtimes."} end
	return true
end
function Simulators.runtimeCommand(row, kept)
	local ok, err = Simulators.validateRuntime(row, kept)
	if not ok then return nil, err end
	return {"/usr/bin/xcrun", "simctl", "runtime", "delete", row.id}
end
function Simulators.runtimeImpact(row)
	return "Delete " .. row.name .. "?\n" .. row.id .. "\n\nRemoves this simulator operating system (" .. row.size .. "). "
		.. (row.devices > 0 and (row.deviceText .. " using it will become unavailable; their data stays until you delete them. ") or "")
		.. "Xcode can download it again from Settings › Components."
end

-- `kept(id)`, when given, says whether Keep protects a location or a device
-- (Locations.keeps): the Simulators category, or the device itself.
function Simulators.validate(action, row, kept)
	if action ~= "erase" and action ~= "delete" then return false, {code = "unsupported_action", message = "Simulator action is not supported."} end
	if not row then return false, {code = "missing_device", message = "No simulator device is selected."} end
	if type(row.id) ~= "string" or not row.id:match(UUID) then return false, {code = "invalid_uuid", message = "Simulator identifier is not a UUID."} end
	if row.running == nil then return false, {code = "state_unknown", message = "Device state could not be checked. Retry or manage this device in Xcode."} end
	if row.running then return false, {code = "device_running", message = "Shut down the simulator before changing it."} end
	if action == "erase" and row.available ~= true then return false, {code = "device_unavailable", message = "Unavailable simulators cannot be erased."} end
	if kept then
		if kept("simulators") then return false, {code = "kept_resource", message = "Keep protects simulator storage."} end
		if kept(Simulators.keepKey(row.id)) then return false, {code = "kept_device", message = "This device is marked Keep."} end
	end
	return true
end
-- Keep for one device, beside Keep for the whole Simulators category. The
-- device's identifier is the key, so the choice survives renames.
function Simulators.keepKey(udid) return "simulator:" .. tostring(udid) end
function Simulators.command(action, row, kept)
	local ok, err = Simulators.validate(action, row, kept)
	if not ok then return nil, err end
	return {"/usr/bin/xcrun", "simctl", action, row.id}
end
function Simulators.impact(action, row)
	return (action == "erase" and "Erase contents of " or "Delete ") .. row.name .. "?\n" .. row.runtime .. " · " .. row.id .. "\n\nPermanently removes installed test apps, accounts and device data (" .. row.size .. "). " ..
		(action == "delete" and "The device is also removed. " or "The device remains available. ") .. "Installed runtimes are preserved. This cannot be undone."
end
return Simulators
