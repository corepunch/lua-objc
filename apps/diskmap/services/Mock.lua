local ns = require("AppKit")
local Mock = {}
Mock.__index = Mock

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = copy(child) end
	return result
end

local function within(path, root)
	if path == root then return true end
	if root == "/" then return path:sub(1, 1) == "/" end
	return path:sub(1, #root + 1) == root .. "/"
end

local function absolute(path, home)
	assert(type(path) == "string", "Mock paths must be strings")
	assert(path:sub(1, 1) == "/" or path == "~" or path:sub(1, 2) == "~/", "Mock paths must be absolute or home-relative")
	if path == "~" then return home end
	if path:sub(1, 2) == "~/" then return home .. path:sub(2) end
	return path
end

local function fixturePath()
	local source = assert(package.searchpath("apps.diskmap.services.Mock", package.path), "Cannot locate Diskmap mock provider")
	return (source:gsub("services/Mock.lua$", "mock-hdd.json"))
end

local function loadFixture(path)
	local file = assert(io.open(path or fixturePath(), "rb"), "Cannot read the bundled Mock HDD fixture")
	local body = file:read("*a")
	file:close()
	local ok, fixture = pcall(ns.json_parse, body)
	assert(ok and type(fixture) == "table" and fixture.format == 1 and type(fixture.items) == "table", "Mock HDD fixture is invalid")
	return fixture
end

local function json(value)
	if type(value) == "string" then
		return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
			local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
			return escapes[character] or string.format("\\u%04x", character:byte())
		end) .. '"'
	end
	if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
	if type(value) ~= "table" then return "null" end
	local count, max = 0, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then count = -1; break end
		count = count + 1; max = math.max(max, key)
	end
	local result = {}
	if count >= 0 and count == max then
		for index = 1, max do result[index] = json(value[index]) end
		return "[" .. table.concat(result, ",") .. "]"
	end
	for key, child in pairs(value) do result[#result + 1] = json(tostring(key)) .. ":" .. json(child) end
	return "{" .. table.concat(result, ",") .. "}"
end

function Mock.new(options)
	options = options or {}
	local home = options.home or os.getenv("HOME") or "/Users"
	local fixture = loadFixture(options.fixturePath)
	local items = {}
	for _, item in ipairs(fixture.items) do
		assert(type(item.path) == "string" and type(item.allocatedBytes) == "number" and item.allocatedBytes >= 0, "Mock HDD entries need a path and nonnegative allocatedBytes")
		items[#items + 1] = {path = absolute(item.path, home), allocatedBytes = item.allocatedBytes}
	end
	local discovery = copy(fixture.discovery or {})
	for _, entry in ipairs(discovery) do entry.path = absolute(entry.path, home) end
	local agents = copy(fixture.agentEntries or {})
	for _, entry in ipairs(agents) do entry.path = absolute(entry.path, home) end
	local service = setmetatable({
		mock = true,
		label = "Mock HDD",
		home = home,
		fixture = fixture,
		items = items,
		discovery = discovery,
		agents = agents,
		availableBytes = fixture.availableBytes,
		kept = {},
		monitoring = false,
	}, Mock)
	for name, method in pairs(Mock) do
		if name ~= "new" and type(method) == "function" then
			if name == "decode" then service[name] = method
			else
				local boundMethod = method
				service[name] = function(...) return boundMethod(service, ...) end
			end
		end
	end
	return service
end

function Mock:scan(paths, exclusions)
	local trees, rootStates, visited = {}, {}, 0
	for index, rawRoot in ipairs(paths) do
		local root, exists, bytes = absolute(rawRoot, self.home), false, 0
		for _, item in ipairs(self.items) do
			if within(item.path, root) then
				exists = true
				local excluded = false
				for _, rawExclusion in ipairs(exclusions or {}) do
					local exclusion = absolute(rawExclusion, self.home)
					if exclusion ~= root and within(exclusion, root) and within(item.path, exclusion) then excluded = true; break end
				end
				if not excluded then bytes = bytes + item.allocatedBytes; visited = visited + 1 end
			end
		end
		if exists then
			trees[index] = {kb = bytes / 1024}
			rootStates[index] = "measured"
		else
			rootStates[index] = "missing"
		end
	end
	return {trees = trees, rootStates = rootStates, completed = #paths, total = #paths, visited = visited,
		seconds = 0, errors = 0, issues = {}, failure = ""}
end

function Mock:start(paths, exclusions)
	return {result = self.scan(paths, exclusions), cancelled = false}
end

function Mock:cancel(job)
	if job then job.cancelled = true end
end

function Mock:poll(job)
	if job.cancelled then return true, {failure = "Measurement cancelled."} end
	return true, job.result
end

function Mock:await(job, completion, progress)
	if job.cancelled then return end
	if progress and job.result.total > 0 then progress(job.result) end
	if not job.cancelled then completion(job.result) end
end

function Mock:diskSpace()
	return {totalKb = self.fixture.capacityBytes / 1024, freeKb = self.availableBytes / 1024}
end

function Mock:discoverEntries(_, completion)
	completion(copy(self.discovery))
end

function Mock:agentEntries()
	return copy(self.agents)
end

function Mock:loadKeep()
	return copy(self.kept)
end

function Mock:saveKeep(kept)
	self.kept = copy(kept)
	return true
end

function Mock:loadSettings()
	return self.monitoring
end

function Mock:saveSettings(enabled)
	self.monitoring = enabled == true
	return true
end

function Mock:monitor()
	-- Mock scans never run on a timer.
end

function Mock:confirmTrash(row)
	return ns.Alert {title = "Move " .. row.name .. " to Mock Trash?", message = row.path .. "\n\nOnly the in-memory mock inventory changes. Restarting restores the fixture.", buttons = {"Cancel", "Move to Trash"}} == 2
end

function Mock:confirmEmptyTrash(_, size)
	return ns.Alert {title = "Empty Mock Trash?", message = "Permanently removes " .. size .. " from this in-memory mock session. Restarting restores the fixture.", buttons = {"Cancel", "Empty Mock Trash"}} == 2
end

function Mock:confirmOwnerCleanup(row, size)
	return ns.Alert {title = "Clear mock " .. row.name .. "?", message = "Mock allocation: " .. size .. "\n\nOnly the in-memory mock inventory changes. Restarting restores the fixture.", buttons = {"Cancel", "Clear Cache"}} == 2
end

function Mock:confirmAction(title, message)
	return ns.Alert {title = title, message = message, buttons = {"Cancel", title}} == 2
end

function Mock:showError(title, message)
	ns.Alert {title = title, message = message}
end

function Mock:openOwner(owner)
	ns.Alert {title = "Mock HDD", message = "Mock mode does not launch " .. tostring(owner) .. ".", buttons = {"OK"}}
end

function Mock:reveal(path)
	ns.Alert {title = "Mock HDD", message = path .. " is a virtual path. Finder is not opened.", buttons = {"OK"}}
	return true
end

local function countUnder(items, path)
	local total = 0
	for _, item in ipairs(items) do if within(item.path, path) then total = total + item.allocatedBytes end end
	return total
end

function Mock:removeUnder(path)
	local kept, removed = {}, 0
	for _, item in ipairs(self.items) do
		if within(item.path, path) then removed = removed + item.allocatedBytes
		else kept[#kept + 1] = item end
	end
	self.items = kept
	return removed
end

function Mock:trash(path)
	path = absolute(path, self.home)
	local moved = {}
	for _, item in ipairs(self.items) do
		if within(item.path, path) then moved[#moved + 1] = item end
	end
	if #moved == 0 then return false, "That virtual path is empty." end
	local name = path:match("([^/]+)$") or "Mock item"
	local destination = self.home .. "/.Trash/" .. name
	local suffix = 2
	while countUnder(self.items, destination) > 0 do destination = self.home .. "/.Trash/" .. name .. " (" .. suffix .. ")"; suffix = suffix + 1 end
	self.removeUnder(path)
	for _, item in ipairs(moved) do
		local relative = item.path == path and "" or item.path:sub(#path + 2)
		item.path = relative == "" and destination or destination .. "/" .. relative
		self.items[#self.items + 1] = item
	end
	return true
end

function Mock:emptyTrash()
	local removed = self.removeUnder(self.home .. "/.Trash")
	self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + removed)
	return true
end

function Mock:runOwnerCleanup(commandId, home, completion)
	local paths = { ["npm-cache"] = home .. "/.npm/_cacache", ["pip-cache"] = home .. "/Library/Caches/pip" }
	local path = paths[commandId]
	if not path then completion(false, "Unsupported mock cache operation."); return end
	local removed = self.removeUnder(path)
	self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + removed)
	completion(true, "Mock cache cleared.")
end

function Mock:snapshotCount(completion)
	completion(self.fixture.snapshotCount or 0, copy(self.fixture.snapshotDates or {}))
end

function Mock.decode(body)
	return ns.json_parse(body)
end

function Mock:command(arguments, completion)
	if arguments[1] ~= "/usr/bin/xcrun" or arguments[2] ~= "simctl" then
		completion(false, "Mock HDD never runs external commands.")
		return
	end
	local simulators = self.fixture.simulators or {runtimes = {}, devices = {}}
	if arguments[3] == "list" and arguments[4] == "--json" then
		local value = copy(simulators)
		for _, devices in pairs(value.devices or {}) do
			for _, device in ipairs(devices) do
				if device.dataPath then
					device.dataPath = absolute(device.dataPath, self.home)
					device.dataPathSize = countUnder(self.items, device.dataPath)
				end
			end
		end
		completion(true, json(value))
		return
	end
	local action, id = arguments[3], arguments[4]
	local matchGroup, matchIndex, device
	for runtime, devices in pairs(simulators.devices or {}) do
		for index, candidate in ipairs(devices) do
			if candidate.udid == id then matchGroup, matchIndex, device = devices, index, candidate; break end
		end
		if device then break end
	end
	if not device or (action ~= "erase" and action ~= "delete") then completion(false, "Mock simulator action is unavailable."); return end
	local path = absolute(device.dataPath or ("~/Library/Developer/CoreSimulator/Devices/" .. id .. "/data"), self.home)
	if action == "erase" then
		local removed = self.removeUnder(path)
		self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + removed)
	else
		local deviceRoot = path:match("^(.*)/data$") or path
		local removed = self.removeUnder(deviceRoot)
		self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + removed)
		table.remove(matchGroup, matchIndex)
	end
	completion(true, "Mock simulator " .. action .. " completed.")
end

function Mock:openSettings(section)
	ns.Alert {title = "Mock HDD", message = "Mock mode does not open System Settings" .. (section and (" (" .. section .. ")") or "") .. ".", buttons = {"OK"}}
end

return Mock
