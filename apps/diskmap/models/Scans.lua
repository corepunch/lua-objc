local Model = require("data.model")
local Knowledge = require("apps.diskmap.knowledge.Paths")
local Locations = require("apps.diskmap.models.Locations")
local Format = require("apps.diskmap.helpers.Format")

local percent = Format.percent

-- The running or last scan: the store's `scan` row ({running, errors,
-- protected, visited, issues, completedAt, failure, ...}) and everything a
-- scan writes beside it: each location's measurement, the files it ranked
-- and each location's immediate children. The scan service
-- (services/Scan.lua) walks the disk and stores what it found through here;
-- pages ask here what the scan covered and what it could not read.
local Scans = Model:extend("scan", {source = function(db) return {db.scan} end})

-- Every byte measured so far.
function Scans:measured()
	local bytes = 0
	for _, m in pairs(Model.db.measurements) do bytes = bytes + (m.bytes or 0) end
	return bytes
end

-- Always use one complete batch: hard links must keep a single owner across refreshes.
-- Locations no app can read (`model.protected`, from knowledge/Filesystem)
-- are skipped by every walk; a resource that is one reads "Protected". A
-- resource that is an APFS volume (`volume` names its role) takes the
-- volume's own used space from `model.volumeUsage` instead of a walk.
function Scans:plan()
	local model = Model.db
	local paths, ids, exclusions = {}, {}, {table.unpack(Knowledge.scanExclusions)}
	local protected = {}
	for _, location in ipairs(model.protected or {}) do
		protected[location.path] = true
		table.insert(exclusions, location.path)
	end
	for _, row in ipairs(Locations:leaves()) do
		if row.path then
			local volume = row.volume and model.volumeUsage and model.volumeUsage[row.volume]
			if protected[row.path] then
				model.measurements[row.id] = {status = "protected"}
			elseif volume then
				model.measurements[row.id] = {bytes = volume, status = "complete", volume = true}
			elseif not row.mediaAccess or model.includeMedia then
				table.insert(paths, row.path); table.insert(ids, row.id)
			else
				model.measurements[row.id] = {status = "excluded"}
			end
			table.insert(exclusions, row.path)
		end
	end
	if not model.includeMedia then
		for _, relative in ipairs(Knowledge.mediaLibraries) do
			table.insert(exclusions, model.home .. relative)
		end
	end
	return paths, ids, exclusions
end
-- The same walk that measures categories also ranks large files, totals file
-- extensions and lists each location's immediate children, so Large Files,
-- File Types and Applications never need a second pass over the disk.
Scans.fileSummary = {files = 500, minimumFileBytes = 50e6, oldDays = 365}
function Scans.options(now)
	return {files = Scans.fileSummary.files, minimumFileBytes = Scans.fileSummary.minimumFileBytes,
		oldBefore = (now or os.time()) - Scans.fileSummary.oldDays * 86400, extensions = true, breakdown = true}
end
-- A refresh discards old values before any new result can become visible.
function Scans:begin(ids)
	local model = Model.db
	model.scan = {running = true}
	model.files, model.breakdowns, model.folderSizes = nil, {}, nil
	for _, id in ipairs(ids) do model.measurements[id] = {status = "calculating"} end
end
function Scans:cancel()
	local model = Model.db
	model.scan.running = false
	if model.files then model.files.measuring, model.files.partial = false, true end
	for id, m in pairs(model.measurements) do
		m.currentScan = nil
		if m.status == "calculating" then model.measurements[id] = {status = "notMeasured"} end
	end
end
-- Allocated bytes are what a resource costs this disk; the logical size and
-- the files iCloud evicted explain the difference from what Finder shows.
local function measurement(node, state)
	local tree = type(node) == "table" and node or {}
	-- A location that could not be read at all has no size: "≥ 0 KB" would
	-- read as a measurement of nothing, where the truth is "No access".
	if state == "unreadable" and (tree.kb or 0) == 0 then return {status = "denied"} end
	return {bytes = type(node) == "table" and node.kb * 1024 or state == "missing" and 0 or nil,
		logicalBytes = tree.logicalKb and math.floor(tree.logicalKb * 1024 + 0.5) or nil,
		cloudBytes = tree.cloudKb and math.floor(tree.cloudKb * 1024 + 0.5) or nil, cloudFiles = tree.cloudFiles,
		status = state == "skipped" and "skipped" or state == "missing" and "complete" or type(node) == "table" and (node.partial and "partial" or "complete") or "denied"}
end
-- Files evicted to iCloud across every measured resource: they use no space
-- on this Mac and would download if opened.
function Scans:cloud()
	local model = Model.db
	local bytes, files = 0, 0
	for _, row in ipairs(Locations:leaves()) do
		local m = model.measurements[row.id]
		if m and m.cloudFiles then bytes, files = bytes + (m.cloudBytes or 0), files + m.cloudFiles end
	end
	return bytes, files
end
local function fileSummary(model, result, measuring)
	if result.largeFiles or result.extensions then
		model.files = {large = result.largeFiles or {}, old = result.oldFiles or {}, extensions = result.extensions or {},
			oldBytes = result.oldBytes or 0, oldCount = result.oldCount or 0,
			partial = measuring or result.partial == true, measuring = measuring}
	end
end
function Scans:progress(ids, result)
	local model = Model.db
	fileSummary(model, result, true)
	model.scan = {running = true, errors = result.errors or 0, protected = result.protected or 0, visited = result.visited or 0,
		completed = result.completed or 0, total = result.total or #ids, seconds = result.seconds or 0, currentPath = result.currentPath}
	for i = 1, math.min(result.completed or 0, #ids) do
		local state = result.rootStates and result.rootStates[i]
		if state then
			model.measurements[ids[i]] = measurement(result.trees and result.trees[i], state)
			model.measurements[ids[i]].currentScan = true
		end
	end
end
function Scans:apply(ids, result)
	local model = Model.db
	model.scan = {completedAt = os.time(), errors = result.errors or 0, protected = result.protected or 0, visited = result.visited or 0, seconds = result.seconds or 0, issues = result.issues or {}, failure = result.failure}
	fileSummary(model, result, false)
	model.breakdowns = {}
	for i, id in ipairs(ids) do
		local children = result.breakdowns and result.breakdowns[i]
		if type(children) == "table" then model.breakdowns[id] = children end
	end
	for i, id in ipairs(ids) do
		local node = result.trees and result.trees[i]
		local state = result.rootStates and result.rootStates[i]
		if result.failure and result.failure ~= "" and not state then
			local current = model.measurements[id]
			-- Keep only results delivered by this scan; pending roots have no value.
			if not current or not current.currentScan then
				model.measurements[id] = {status = "failed"}
			end
			if current then current.currentScan = nil end
		else
			model.measurements[id] = measurement(node, state)
		end
	end
end

-- The scan measures once; after that the model is changed, not measured
-- again. `remove` takes `path` out of every measurement once it has left
-- the disk or moved: locations at or under it measure zero, the location
-- holding it, that location's immediate child holding it and the file
-- rankings lose what it took. `bytes` is what the path took, as the page
-- that removed it measured it. `to`, when given, is where it went (the
-- Trash, a folder picked for Move to…): the location holding `to` grows by
-- as much, so moving to the Trash frees nothing until the Trash is emptied.
local function within(path, root) return path == root or path:sub(1, #root + 1) == root .. "/" end
local function parentOf(path) return path:match("^(.+)/[^/]+$") end
local function shrink(m, bytes)
	if not m or not m.bytes then return end
	m.bytes = math.max(0, m.bytes - bytes)
	if m.logicalBytes then m.logicalBytes = math.max(0, m.logicalBytes - bytes) end
end
function Scans:remove(path, bytes, to)
	local model = Model.db
	if type(path) ~= "string" or path == "" then return end
	bytes = bytes or 0
	local nested = 0
	for _, row in ipairs(Locations:leaves()) do
		local m = row.path and within(row.path, path) and model.measurements[row.id]
		if m then
			nested = nested + (m.bytes or 0)
			model.measurements[row.id] = {bytes = 0, status = "complete"}
			if model.breakdowns then model.breakdowns[row.id] = nil end
		end
	end
	local rest = math.max(0, bytes - nested)
	local owner = parentOf(path) and Locations:owner(parentOf(path))
	if owner and rest > 0 then
		shrink(model.measurements[owner.id], rest)
		local children = model.breakdowns and model.breakdowns[owner.id]
		for index = #(children or {}), 1, -1 do
			local child = children[index]
			local childPath = owner.path .. "/" .. child.name
			if childPath == path then table.remove(children, index)
			elseif within(path, childPath) then child.kb = math.max(0, child.kb - rest / 1024) end
		end
	end
	local files = model.files
	if files then
		local extensions = {}
		for _, row in ipairs(files.extensions or {}) do extensions[row.extension] = row end
		local function drop(list, old)
			for index = #(list or {}), 1, -1 do
				local file = list[index]
				if within(file.path, path) then
					table.remove(list, index)
					if old then
						files.oldBytes, files.oldCount = math.max(0, (files.oldBytes or 0) - file.bytes), math.max(0, (files.oldCount or 0) - 1)
					else
						local extension = extensions[(file.path:match("[^/]%.([^./]+)$") or ""):lower()]
						if extension then
							extension.bytes, extension.count = math.max(0, extension.bytes - file.bytes), math.max(0, extension.count - 1)
						end
					end
				end
			end
		end
		drop(files.large, false)
		drop(files.old, true)
	end
	local destination = to and Locations:owner(to)
	local m = destination and model.measurements[destination.id]
	if m and m.bytes then m.bytes = m.bytes + bytes end
end

-- A location whose owner cleaned it (a package manager's cache command)
-- takes the size measured of that one folder afterward.
function Scans:resize(id, bytes)
	local model = Model.db
	model.measurements[id] = {bytes = bytes, status = "complete"}
	if model.breakdowns then model.breakdowns[id] = nil end
	if model.files then
		local row = Locations:find(id)
		if row and row.path then
			for _, list in ipairs({model.files.large or {}, model.files.old or {}}) do
				for index = #list, 1, -1 do if within(list[index].path, row.path) then table.remove(list, index) end end
			end
		end
	end
end

-- Volume summary for the hero card. Capacity numbers come from the system
-- volume query; measured totals come from the ledger and never replace them.
function Scans:summary(disk, capacity)
	local result = {measured = Format.size(Scans:measured())}
	if not disk or not disk.totalKb or disk.totalKb <= 0 then
		result.available = false
		result.used, result.total, result.free = "—", "Capacity unavailable", "—"
		result.caption = "Capacity unavailable"
		return result
	end
	local total, free = disk.totalKb * 1024, disk.freeKb * 1024
	result.available = true
	result.used, result.total, result.free = Format.size(total - free), Format.size(total), Format.size(free)
	result.usedPercent = percent(total - free, total)
	result.caption = "of " .. result.total .. " used"
	result.subtitle = result.free .. " free of " .. result.total
	result.short = result.subtitle
	-- Finder's "available" adds purgeable storage macOS will release on demand.
	-- The window subtitle has room for one number, so it takes Finder's; the
	-- Overview card states free and available apart.
	if capacity and capacity.important and capacity.important > free then
		result.availableText = Format.size(capacity.important)
		result.subtitle = result.free .. " free · " .. result.availableText .. " available of " .. result.total
		result.short = result.availableText .. " available of " .. result.total
	end
	result.lowSpace = free / total < 0.1
	result.lowSpaceMessage = result.lowSpace and "Less than 10% of this disk is free" or nil
	return result
end

-- Locations macOS keeps from every app: the known ones present here
-- (knowledge/Filesystem), which no walk enters, and those the scanner found
-- refusing every process (`refused`, part of the scan's error total). With
-- Full Disk Access on, every remaining refusal is one no permission lifts.
-- Their space stays in the used total, so it reads as not attributed.
function Scans:protected(fullDiskAccess)
	local model = Model.db
	local names, seen = {}, {}
	for _, location in ipairs(model.protected or {}) do
		local name = location.feature or location.name
		if not seen[name] then seen[name] = true; table.insert(names, name) end
	end
	local scan = model.scan or {}
	local refused = fullDiskAccess == true and (scan.errors or 0) or (scan.protected or 0)
	local count = #(model.protected or {}) + refused
	local detail = "No app can read these, with any permission; their space counts as not attributed"
	if #names > 0 then detail = table.concat(names, ", ") .. (refused > 0 and " and other system folders" or "") .. ". " .. detail end
	return {count = count, refused = refused, names = names, detail = detail}
end

Scans.protectedNames = 4

-- The folders the last scan could not read, for the notice that offers Full
-- Disk Access: at most `limit` paths, shown from the home folder, and how
-- many more there were. The scan keeps the first thousand paths and goes on
-- counting, so the count of the rest comes from its error total: the notice
-- and the "Unreadable locations" row then name the same number. Folders
-- System Integrity Protection guards are left out: Full Disk Access cannot
-- open them, so the notice would promise what it cannot deliver.
Scans.unreadableLimit = 6
function Scans:unreadable(limit)
	local model = Model.db
	limit = limit or Scans.unreadableLimit
	local paths, seen, total = {}, {}, 0
	local home = model.home or ""
	for _, issue in ipairs(model.scan and model.scan.issues or {}) do
		local path = issue.path
		if type(path) == "string" and not issue.protected and not seen[path] then
			seen[path] = true
			total = total + 1
			if #paths < limit then
				if home ~= "" and path:sub(1, #home + 1) == home .. "/" then path = "~" .. path:sub(#home + 1) end
				table.insert(paths, path)
			end
		end
	end
	total = math.max(total, math.floor(model.scan and (model.scan.errors or 0) - (model.scan.protected or 0) or 0))
	return {paths = paths, more = math.max(0, total - #paths), moreText = Format.count(math.max(0, total - #paths)), total = total}
end

-- Coverage of the latest scan as one sentence.
function Scans:coverage()
	local model = Model.db
	local scan = model.scan or {}
	local parts = {}
	if scan.running then table.insert(parts, "scan in progress, totals are still growing") end
	if scan.failure and scan.failure ~= "" then table.insert(parts, "the scan stopped early") end
	local protected = scan.protected or 0
	if protected > 0 then table.insert(parts, protected .. (protected == 1 and " protected location" or " protected locations") .. " not readable without Full Disk Access") end
	if not model.includeMedia then table.insert(parts, "Photos, Music and TV libraries excluded") end
	if #parts == 0 then return "Coverage: complete." end
	return "Coverage: " .. table.concat(parts, "; ") .. "."
end

-- What a person should know about the latest scan, as tips.
function Scans:tips(disk)
	local model = Model.db
	local tips = {}
	if (model.scan.errors or 0) > 0 then
		table.insert(tips, {id = "access", icon = "lock.shield", title = "Some files could not be measured",
			text = tostring(model.scan.errors) .. " filesystem read issues were reported. Full Disk Access may improve coverage; some locations can still be unavailable. Refresh to retry. The unassigned amount is not a cleanup estimate.",
			action = "settings", actionTitle = "Review access options"})
	end
	if disk and disk.totalKb > 0 and disk.freeKb / disk.totalKb < 0.1 then
		table.insert(tips, {id = "capacity", icon = "externaldrive.badge.exclamationmark", title = "Available space is low",
			text = "Less than 10% of this disk is available. Review the measured candidates on this page and back up personal data before removing anything."})
	end
	local count = require("apps.diskmap.models.Keeps"):resourceCount()
	if count > 0 then
		table.insert(tips, {id = "kept", icon = "checkmark.shield", title = "Kept resources stay protected",
			text = tostring(count) .. " resources are marked Keep. Their descendants are excluded from cleanup suggestions.", action = "storage", actionTitle = "Browse resources"})
	end
	table.insert(tips, {id = "system", icon = "shield.lefthalf.filled", title = "macOS manages system storage",
		text = "Preboot, Recovery and local snapshots are system managed. File scans cannot attribute exclusive snapshot allocation. No manual cleanup is offered.", action = "system", actionTitle = "Learn about system storage"})
	return tips
end

return Scans
