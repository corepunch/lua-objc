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

local function buildIndex(items)
	local totals, counts = {}, {}
	for _, item in ipairs(items) do
		local ancestor = item.path
		while ancestor and ancestor ~= "" do
			totals[ancestor] = (totals[ancestor] or 0) + item.countedBytes
			counts[ancestor] = (counts[ancestor] or 0) + 1
			if ancestor == "/" then break end
			local slash = ancestor:match("^.*()/")
			ancestor = slash == 1 and "/" or slash and ancestor:sub(1, slash - 1)
		end
	end
	return totals, counts
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
	return (source:gsub("services/Mock.lua$", "mock-hdd.bin"))
end

local MAX_SAFE_INTEGER = 9007199254740991
local function readBinaryFixture(file)
	local buffer, position = "", 1
	local function readExact(length)
		assert(length >= 0 and length <= 1024 * 1024, "Mock HDD snapshot record is too large")
		if length == 0 then return "" end
		local chunks, remaining = {}, length
		while remaining > 0 do
			if position > #buffer then
				buffer = assert(file:read(64 * 1024), "Mock HDD snapshot is truncated")
				position = 1
			end
			local count = math.min(remaining, #buffer - position + 1)
			table.insert(chunks, (buffer:sub(position, position + count - 1)))
			position = position + count
			remaining = remaining - count
		end
		return #chunks == 1 and chunks[1] or table.concat(chunks)
	end
	local function little32(bytes, offset)
		local a, b, c, d = bytes:byte(offset, offset + 3)
		return a + b * 256 + c * 65536 + d * 16777216
	end
	local function little64(bytes, offset)
		local low, high = little32(bytes, offset), little32(bytes, offset + 4)
		assert(high <= 2097151, "Mock HDD snapshot number exceeds Lua's exact integer range")
		return high * 4294967296 + low
	end

	local header = readExact(56)
	assert(header:sub(1, 8) == "DMOCK001", "Mock HDD snapshot magic is invalid")
	assert(little32(header, 9) == 1, "Mock HDD snapshot version is unsupported")
	local flags = little32(header, 13)
	assert(flags < 2, "Mock HDD snapshot flags are unsupported")
	local capacityBytes, availableBytes = little64(header, 17), little64(header, 25)
	local itemCount, errors, visited = little64(header, 33), little64(header, 41), little64(header, 49)
	assert(itemCount <= 50000000, "Mock HDD snapshot has too many entries")
	local items, previous = {}, ""
	for index = 1, itemCount do
		local record = readExact(24)
		local prefixLength, suffixLength = little32(record, 1), little32(record, 5)
		local allocatedBytes, countedBytes = little64(record, 9), little64(record, 17)
		assert(prefixLength <= #previous, "Mock HDD snapshot path prefix is invalid")
		local path = previous:sub(1, prefixLength) .. readExact(suffixLength)
		local rooted = path:sub(1, 1) == "/" or path == "~" or path:sub(1, 2) == "~/"
		assert(rooted and not path:find("\0", 1, true), "Mock HDD snapshot path is invalid")
		items[index] = {path = path, allocatedBytes = allocatedBytes, countedBytes = countedBytes}
		previous = path
	end
	assert(position > #buffer and file:read(1) == nil, "Mock HDD snapshot has trailing data")
	return {
		capacityBytes = capacityBytes,
		availableBytes = availableBytes,
		partial = flags % 2 == 1,
		errors = errors,
		visited = visited,
		items = items,
	}
end

local function loadFixture(path)
	local selectedPath = path or fixturePath()
	local file = assert(io.open(selectedPath, "rb"), "Cannot read the Mock HDD snapshot")
	local ok, fixture = pcall(readBinaryFixture, file)
	file:close()
	assert(ok, fixture)
	if not path then
		local profile = require("apps.diskmap.services.MockProfile")
		for key, value in pairs(profile) do fixture[key] = copy(value) end
	end
	assert(type(fixture.capacityBytes) == "number" and fixture.capacityBytes >= 0 and fixture.capacityBytes <= MAX_SAFE_INTEGER
		and type(fixture.availableBytes) == "number" and fixture.availableBytes >= 0 and fixture.availableBytes <= MAX_SAFE_INTEGER,
		"Mock HDD snapshot capacity metadata is invalid")
	assert(type(fixture.items) == "table", "Mock HDD snapshot is invalid")
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
	for key, child in pairs(value) do table.insert(result, json(tostring(key)) .. ":" .. json(child)) end
	return "{" .. table.concat(result, ",") .. "}"
end

function Mock.new(options)
	options = options or {}
	local home = options.home or os.getenv("HOME") or "/Users"
	local fixture = loadFixture(options.fixturePath)
	local items = fixture.items
	for _, item in ipairs(fixture.items) do
		assert(type(item.path) == "string" and type(item.allocatedBytes) == "number" and item.allocatedBytes >= 0, "Mock HDD entries need a path and nonnegative allocatedBytes")
		local countedBytes = item.countedBytes == nil and item.allocatedBytes or item.countedBytes
		assert(type(countedBytes) == "number" and countedBytes >= 0, "Mock HDD entries need nonnegative countedBytes")
		item.path = absolute(item.path, home)
		item.countedBytes = countedBytes
		for key in pairs(item) do
			if key ~= "path" and key ~= "allocatedBytes" and key ~= "countedBytes" then item[key] = nil end
		end
	end
	-- The synthetic profile layers extra files over the binary fixture and
	-- dates files by days since last use; exported snapshots carry no dates.
	local now = os.time()
	for _, extra in ipairs(fixture.extraItems or {}) do
		table.insert(items, {path = absolute(extra.path, home), allocatedBytes = extra.bytes, countedBytes = extra.bytes})
	end
	local ages = {}
	for path, days in pairs(fixture.fileAges or {}) do ages[absolute(path, home)] = days end
	for _, extra in ipairs(fixture.extraItems or {}) do ages[absolute(extra.path, home)] = extra.usedDaysAgo end
	for _, item in ipairs(items) do
		item.used = now - (ages[item.path] or fixture.defaultAgeDays or 0) * 86400
	end
	fixture.items, fixture.extraItems = nil, nil
	collectgarbage("collect")
	local totals, counts = buildIndex(items)
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
		totals = totals,
		fileCounts = counts,
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

function Mock:scan(paths, exclusions, options)
	local trees, rootStates, visited = {}, {}, 0
	for index, rawRoot in ipairs(paths) do
		local root = absolute(rawRoot, self.home)
		local bytes, count = self.totals[root] or 0, self.fileCounts[root] or 0
		local relevantExclusions = {}
		for _, rawExclusion in ipairs(exclusions or {}) do
			local exclusion = absolute(rawExclusion, self.home)
			if exclusion ~= root and within(exclusion, root) then table.insert(relevantExclusions, exclusion) end
		end
		table.sort(relevantExclusions, function(a, b) return #a < #b end)
		local selectedExclusions = {}
		for _, exclusion in ipairs(relevantExclusions) do
			local covered = false
			for _, parent in ipairs(selectedExclusions) do if within(exclusion, parent) then covered = true; break end end
			if not covered then
				bytes = bytes - (self.totals[exclusion] or 0)
				count = count - (self.fileCounts[exclusion] or 0)
				table.insert(selectedExclusions, exclusion)
			end
		end
		visited = visited + count
		local exists = self.fileCounts[root] ~= nil
		if exists then
			trees[index] = {kb = math.max(0, bytes) / 1024, partial = self.fixture.partial == true}
			rootStates[index] = "measured"
		else
			rootStates[index] = self.fixture.partial == true and "unreadable" or "missing"
		end
	end
	local result = {trees = trees, rootStates = rootStates, completed = #paths, total = #paths, visited = visited,
		seconds = 0, errors = self.fixture.errors or 0, issues = {}, failure = "", partial = self.fixture.partial == true}
	if options then self.summarize(result, paths, exclusions, options) end
	return result
end

-- The native scanner's optional summaries over the in-memory file list. Each
-- file belongs to the deepest requested root above it; an exclusion met first
-- hides it, exactly as the native walk never descends into excluded paths.
function Mock:summarize(result, paths, exclusions, options)
	local roots, excluded = {}, {}
	for index, path in ipairs(paths) do roots[absolute(path, self.home)] = index end
	for _, path in ipairs(exclusions or {}) do excluded[absolute(path, self.home)] = true end
	local limit, minimum, before = math.min(options.files or 0, 2000), options.minimumFileBytes or 0, options.oldBefore or 0
	local large, old, extensions, breakdowns = {}, {}, {}, {}
	local oldBytes, oldCount = 0, 0
	for index in ipairs(paths) do breakdowns[index] = {} end
	for _, item in ipairs(self.items) do
		local ancestor, owner, child = item.path, nil, nil
		while ancestor do
			if roots[ancestor] then owner = roots[ancestor]; break end
			if excluded[ancestor] then break end
			child = ancestor
			local slash = ancestor:match("^.*()/")
			ancestor = slash == 1 and ancestor ~= "/" and "/" or slash and slash > 1 and ancestor:sub(1, slash - 1) or nil
		end
		if owner and item.countedBytes > 0 then
			local bytes = item.countedBytes
			local isOld = before > 0 and item.used and item.used < before
			if isOld then oldBytes, oldCount = oldBytes + bytes, oldCount + 1 end
			if options.extensions then
				local extension = (item.path:match("[^/]%.([^./]+)$") or ""):lower()
				if #extension > 12 then extension = "" end
				local row = extensions[extension] or {extension = extension, bytes = 0, count = 0, oldBytes = 0}
				row.bytes, row.count = row.bytes + bytes, row.count + 1
				if isOld then row.oldBytes = row.oldBytes + bytes end
				extensions[extension] = row
			end
			if limit > 0 and bytes >= minimum then
				local file = {path = item.path, bytes = bytes, modified = item.used, used = item.used}
				table.insert(large, file)
				if isOld then table.insert(old, file) end
			end
			if options.breakdown and child then
				local name = child:match("([^/]+)$")
				local rows = breakdowns[owner]
				rows[name] = rows[name] or {name = name, kb = 0, directory = child ~= item.path}
				rows[name].kb = rows[name].kb + bytes / 1024
			end
		end
	end
	local function ranked(files)
		table.sort(files, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.path < b.path end)
		while #files > limit do table.remove(files) end
		return files
	end
	if limit > 0 then result.largeFiles, result.oldFiles = ranked(large), ranked(old) end
	if options.extensions then
		result.extensions = {}
		for _, row in pairs(extensions) do table.insert(result.extensions, row) end
	end
	if options.breakdown then
		result.breakdowns = {}
		for index, rows in ipairs(breakdowns) do
			local list = {}
			for _, row in pairs(rows) do table.insert(list, row) end
			table.sort(list, function(a, b) return a.name < b.name end)
			result.breakdowns[index] = list
		end
	end
	if before > 0 then result.oldBytes, result.oldCount = oldBytes, oldCount end
end

function Mock:start(paths, exclusions, options)
	return {result = self.scan(paths, exclusions, options), cancelled = false}
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

function Mock:reindex()
	self.totals, self.fileCounts = buildIndex(self.items)
end

local function countUnder(service, path)
	return service.totals[path] or 0
end

function Mock:removeUnder(path)
	local kept, removed = {}, countUnder(self, path)
	for _, item in ipairs(self.items) do
		if within(item.path, path) then
		else table.insert(kept, item) end
	end
	self.items = kept
	self.reindex()
	return removed
end

function Mock:trash(path)
	path = absolute(path, self.home)
	local moved = {}
	for _, item in ipairs(self.items) do
		if within(item.path, path) then table.insert(moved, item) end
	end
	if #moved == 0 then return false, "That virtual path is empty." end
	local name = path:match("([^/]+)$") or "Mock item"
	local destination = self.home .. "/.Trash/" .. name
	local suffix = 2
	while (self.fileCounts[destination] or 0) > 0 do destination = self.home .. "/.Trash/" .. name .. " (" .. suffix .. ")"; suffix = suffix + 1 end
	self.removeUnder(path)
	for _, item in ipairs(moved) do
		local relative = item.path == path and "" or item.path:sub(#path + 2)
		item.path = relative == "" and destination or destination .. "/" .. relative
		table.insert(self.items, item)
	end
	self.reindex()
	return true
end

function Mock:emptyTrash()
	local removed = self.removeUnder(self.home .. "/.Trash")
	self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + removed)
	return true
end

function Mock:runOwnerCleanup(commandId, home, completion)
	local paths = { ["npm-cache"] = home .. "/.npm/_cacache", ["pip-cache"] = home .. "/Library/Caches/pip",
		["xcode-previews"] = home .. "/Library/Developer/Xcode/UserData/Previews" }
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

function Mock:children(path)
	path = absolute(path, self.home)
	if path ~= "/" and path:sub(-1) == "/" then path = path:sub(1, -2) end
	local prefix = path == "/" and "/" or path .. "/"
	local seen, rows = {}, {}
	for _, item in ipairs(self.items) do
		if item.path:sub(1, #prefix) == prefix then
			local name = item.path:sub(#prefix + 1):match("^([^/]+)")
			if name and not seen[name] then
				seen[name] = true
				local child = prefix .. name
				table.insert(rows, {name = name, path = child, bytes = self.totals[child] or 0})
			end
		end
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

function Mock:bundles(root, kind)
	if kind ~= "sdk" then return {} end
	root = absolute(root, self.home)
	if root ~= "/" and root:sub(-1) == "/" then root = root:sub(1, -2) end
	local prefix = root .. "/"
	local found = {}
	for _, item in ipairs(self.items) do
		if item.path:sub(1, #prefix) == prefix then
			local relative = item.path:sub(#prefix + 1)
			local sdk = relative:match("^(.-%.sdk)")
			if sdk and (sdk:match("/SDKs/[^/]+%.sdk$") or sdk:match("^SDKs/[^/]+%.sdk$") or sdk:match("^[^/]+%.sdk$")) then found[sdk] = true end
		end
	end
	local rows = {}
	for sdk in pairs(found) do
		local path = prefix .. sdk
		table.insert(rows, {name = sdk:match("([^/]+)%.sdk$"), path = path, bytes = self.totals[path] or 0})
	end
	table.sort(rows, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	return rows
end

function Mock:simulatorRecord(udid)
	local simulators = self.fixture.simulators
	if not simulators then return nil end
	for runtime, devices in pairs(simulators.devices or {}) do
		for _, device in ipairs(devices) do
			if device.udid == udid then return device, runtime end
		end
	end
end

function Mock:readPropertyList(path)
	return ns.readPropertyList(absolute(path, self.home))
end

function Mock:command(arguments, completion)
	if arguments[1] ~= "/usr/bin/xcrun" or arguments[2] ~= "simctl" then
		completion(false, "Mock HDD never runs external commands.")
		return
	end
	local simulators = self.fixture.simulators or {runtimes = {}, devices = {}}
	if arguments[3] == "runtime" and arguments[4] == "delete" then
		local images = self.fixture.simulatorRuntimes or {}
		local image = images[arguments[5]]
		if not image or image.deletable ~= true then completion(false, "Mock runtime is unavailable."); return end
		images[arguments[5]] = nil
		self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + (image.sizeBytes or 0))
		-- As with simctl, devices on a deleted runtime remain but become unavailable.
		for _, device in ipairs((simulators.devices or {})[image.runtimeIdentifier] or {}) do device.isAvailable = false end
		completion(true, "Mock runtime deleted.")
		return
	end
	if arguments[3] == "list" and arguments[4] == "--json" then
		local value = copy(simulators)
		for _, devices in pairs(value.devices or {}) do
			for _, device in ipairs(devices) do
				if device.dataPath then
					device.dataPath = absolute(device.dataPath, self.home)
					device.dataPathSize = countUnder(self, device.dataPath)
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
	local deviceRoot = self.home .. "/Library/Developer/CoreSimulator/Devices/" .. tostring(id or "")
	if not device then
		if (action ~= "erase" and action ~= "delete") or (self.fileCounts[deviceRoot] or 0) == 0 then
			completion(false, "Mock simulator action is unavailable.")
			return
		end
		local removed = self.removeUnder(action == "erase" and (deviceRoot .. "/data") or deviceRoot)
		self.availableBytes = math.min(self.fixture.capacityBytes, self.availableBytes + removed)
		completion(true, "Mock simulator " .. action .. " completed.")
		return
	end
	if action ~= "erase" and action ~= "delete" then completion(false, "Mock simulator action is unavailable."); return end
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

function Mock:simulatorRuntimes(completion)
	completion(copy(self.fixture.simulatorRuntimes or {}))
end

function Mock:applicationInfo(paths, completion)
	local info, now = {}, os.time()
	local known = {}
	for path, value in pairs(self.fixture.applications or {}) do known[absolute(path, self.home)] = value end
	for _, path in ipairs(paths) do
		local value = known[path]
		info[path] = value and {bundleId = value.bundleId, version = value.version,
			lastUsed = value.lastUsedDaysAgo and now - value.lastUsedDaysAgo * 86400} or {}
	end
	completion(info)
end

function Mock:installedBundleIds(completion)
	local ids = {"com.apple.Safari", "com.apple.mail"}
	for _, value in pairs(self.fixture.applications or {}) do table.insert(ids, value.bundleId) end
	completion(ids)
end

function Mock:volumes(completion)
	local volumes = copy(self.fixture.volumes or {})
	-- The container matches the fixture's capacity and follows mock cleanup:
	-- the Data volume holds whatever the fixed-size volumes leave.
	for _, container in ipairs(volumes.apfs and volumes.apfs.Containers or {}) do
		container.CapacityCeiling, container.CapacityFree = self.fixture.capacityBytes, self.availableBytes
		local others, data = 0, nil
		for _, volume in ipairs(container.Volumes or {}) do
			if volume.Roles and volume.Roles[1] == "Data" then data = volume else others = others + (volume.CapacityInUse or 0) end
		end
		if data then data.CapacityInUse = math.max(0, self.fixture.capacityBytes - self.availableBytes - others) end
	end
	completion(volumes)
end

function Mock:openDiskUtility()
	ns.Alert {title = "Mock HDD", message = "Mock mode does not open Disk Utility.", buttons = {"OK"}}
end

function Mock:copy(text)
	ns.copyToClipboard(text)
end

function Mock:confirmTrashPath(title, path)
	return ns.Alert {title = title, message = path .. "\n\nOnly the in-memory mock inventory changes. Restarting restores the fixture.", buttons = {"Cancel", "Move to Trash"}} == 2
end

function Mock:softwareUpdateStatus()
	return copy(self.fixture.softwareUpdate)
end

function Mock:openSettings(section)
	ns.Alert {title = "Mock HDD", message = "Mock mode does not open System Settings" .. (section and (" (" .. section .. ")") or "") .. ".", buttons = {"OK"}}
end

return Mock
