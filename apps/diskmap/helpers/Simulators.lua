local Format = require("apps.diskmap.helpers.Format")
local Simulators = {}
local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
-- Devices not booted for this long are worth a look; the threshold is a
-- review hint, never a deletion rule, and devices without a recorded boot
-- never match.
Simulators.staleDays = 90

-- Days since an ISO 8601 timestamp ("2026-09-20T16:20:00Z"), or nil.
function Simulators.age(timestamp, now)
	if type(timestamp) ~= "string" then return nil end
	local year, month, day = timestamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if not year then return nil end
	local then_ = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12})
	return math.max(0, math.floor(((now or os.time()) - then_) / 86400))
end

local SYMBOLS = {{"ipad", "ipad"}, {"watch", "applewatch"}, {"tv", "appletv"}, {"vision", "vision.pro"}, {"xr", "vision.pro"}}
function Simulators.symbol(name)
	local lowered = (name or ""):lower()
	for _, entry in ipairs(SYMBOLS) do
		if lowered:find(entry[1], 1, true) then return entry[2] end
	end
	return "iphone"
end

-- "iOS 26.0" from a runtime identifier.
function Simulators.runtimeName(identifier)
	if type(identifier) ~= "string" or identifier == "" or identifier == "unknown" then return "Unknown runtime" end
	local body = identifier:gsub("^com%.apple%.CoreSimulator%.SimRuntime%.", "")
	local product, major, minor = body:match("^(%a+)%-(%d+)%-(%d+)$")
	if product then return product .. " " .. major .. "." .. minor end
	return (body:gsub("%-", " "))
end

-- Device rows from simctl's device list joined with the measured device
-- folders: `devices` is `{[runtime] = {{udid, name, state, isAvailable,
-- lastBootedAt, deviceTypeIdentifier}}}`, `folders[udid]` is {path, bytes,
-- used, state}. A device simctl does not list but whose folder exists is
-- orphaned: its data is unreachable from Xcode.
function Simulators.deviceRows(devices, folders, now)
	local rows, seen = {}, {}
	for runtime, list in pairs(devices or {}) do
		for _, device in ipairs(list) do
			seen[device.udid] = true
			local folder = folders[device.udid] or {}
			local name = device.name or "Unnamed device"
			local available = device.isAvailable
			local running
			if device.state == "Shutdown" then running = false
			elseif device.state == "Booted" or device.state == "Booting" or device.state == "Shutting Down" then running = true end
			local age = Simulators.age(device.lastBootedAt, now)
			local row = {id = device.udid, path = folder.path or ("~/Library/Developer/CoreSimulator/Devices/" .. device.udid), udid = device.udid,
				name = name, owner = Simulators.runtimeName(runtime), icon = Simulators.symbol(name),
				available = available, running = running, bytes = folder.bytes, used = folder.used, state = folder.state or "missing",
				runtimeIdentifier = runtime, deviceType = device.deviceTypeIdentifier, age = age,
				detail = available == false and "Unavailable" or (device.state or "State unknown")}
			row.what = "The simulator device " .. name .. " on " .. row.owner .. ": its installed apps, accounts and data."
			if available == false then
				row.verdict, row.action = "safe", "delete"
				row.reason = "Its runtime is no longer installed, so Xcode cannot boot it; only its data remains."
			elseif running then
				row.verdict, row.action = "keep", "none"
				row.reason = "It is running now."
			elseif age and age >= Simulators.staleDays then
				row.verdict, row.action = "review", "erase"
				row.reason = "Not booted for " .. Format.plural(age, "day") .. ". Erasing keeps the device and removes its apps and data; deleting removes the device too."
			else
				row.verdict, row.action = "review", "erase"
				row.reason = (age and ("Booted " .. Format.ago(age):lower() .. ". ") or "Never booted on record. ") .. "Erasing keeps the device and removes its apps and data."
			end
			table.insert(rows, row)
		end
	end
	for udid, folder in pairs(folders or {}) do
		if not seen[udid] then
			table.insert(rows, {id = udid, path = folder.path, udid = udid, name = folder.name or udid, owner = Simulators.runtimeName(folder.runtime),
				icon = Simulators.symbol(folder.name), bytes = folder.bytes, used = folder.used, state = folder.state or "measured",
				available = false, running = false, detail = "Not listed by simctl", verdict = "safe", action = "delete",
				what = "A device folder simctl no longer lists. Xcode cannot reach it.",
				reason = "simctl does not list this device, so only its folder remains."})
		end
	end
	table.sort(rows, function(a, b) if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end; return (a.id or "") < (b.id or "") end)
	return rows
end

local PLATFORMS = {
	["com.apple.platform.iphonesimulator"] = "iOS", ["com.apple.platform.appletvsimulator"] = "tvOS",
	["com.apple.platform.watchsimulator"] = "watchOS", ["com.apple.platform.xrsimulator"] = "visionOS",
}

-- Installed runtimes from `xcrun simctl runtime list -j`: an object keyed
-- by runtime image UUID. Device counts come from the device list.
function Simulators.runtimeRows(list, devices, now)
	local rows, counts = {}, {}
	for runtime, list_ in pairs(devices or {}) do counts[runtime] = #list_ end
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
			local count = counts[entry.runtimeIdentifier] or 0
			local row = {id = "runtime:" .. id, runtimeId = id, name = name, icon = Simulators.symbol(platform), owner = "Simulator",
				detail = count == 0 and "No devices" or Format.plural(count, "device"),
				platform = platform, version = version, runtimeIdentifier = entry.runtimeIdentifier,
				bytes = bytes, state = bytes and "measured" or "failed", deletable = entry.deletable == true, devices = count,
				path = type(entry.path) == "string" and entry.path or nil,
				what = "The " .. name .. " simulator runtime" .. (build and (", build " .. build) or "") .. ": the operating system image simulator devices boot. Xcode downloads it again from Settings › Components."}
			if not row.deletable then
				row.verdict, row.action, row.reason = "keep", "none", "simctl reports it as not deletable: it is the one Xcode bundles, or it is in use."
			elseif count == 0 then
				row.verdict, row.action, row.reason = "safe", "runtimeDelete", "No device uses it" .. (age and (", last used " .. Format.ago(age):lower()) or "") .. "."
			else
				row.verdict, row.action, row.reason = "review", "runtimeDelete", row.detail .. " run on it; they become unavailable without it."
			end
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		if (a.bytes or 0) ~= (b.bytes or 0) then return (a.bytes or 0) > (b.bytes or 0) end
		return a.id < b.id
	end)
	return rows
end

-- The simctl command for an action on a row, or nil with a refusal.
function Simulators.command(action, row)
	if action == "runtimeDelete" then
		if type(row.runtimeId) ~= "string" or not row.runtimeId:match(UUID) then return nil, {message = "Runtime identifier is not a UUID."} end
		if row.deletable ~= true then return nil, {message = "simctl reports this runtime as not deletable; manage it in Xcode."} end
		return {"/usr/bin/xcrun", "simctl", "runtime", "delete", row.runtimeId}
	end
	if action ~= "erase" and action ~= "delete" then return nil, {message = "Simulator action is not supported."} end
	if type(row.udid) ~= "string" or not row.udid:match(UUID) then return nil, {message = "Simulator identifier is not a UUID."} end
	if row.running == nil then return nil, {message = "Device state could not be checked. Retry or manage this device in Xcode."} end
	if row.running then return nil, {message = "Shut down the simulator before changing it."} end
	if action == "erase" and row.available ~= true then return nil, {message = "Unavailable simulators cannot be erased."} end
	return {"/usr/bin/xcrun", "simctl", action, row.udid}
end

-- A device's current record from a fresh simctl listing, as deviceRows
-- reads it, for the check just before an action.
function Simulators.refresh(row, listed)
	for runtime, devices in pairs(listed and listed.devices or {}) do
		for _, device in ipairs(devices) do
			if device.udid == row.udid then
				local fresh = {}
				for key, value in pairs(row) do fresh[key] = value end
				fresh.available = device.isAvailable
				if device.state == "Shutdown" then fresh.running = false
				elseif device.state == "Booted" or device.state == "Booting" or device.state == "Shutting Down" then fresh.running = true
				else fresh.running = nil end
				fresh.runtimeIdentifier = runtime
				return fresh
			end
		end
	end
	return nil
end

return Simulators
