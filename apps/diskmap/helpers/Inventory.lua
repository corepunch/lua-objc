local Model = require("data.model")
local Locations = require("apps.diskmap.models.Locations")
local Inventory = {}
-- Always use one complete batch: hard links must keep a single owner across refreshes.
-- Locations no app can read (`model.protected`, from knowledge/Filesystem)
-- are skipped by every walk; a resource that is one reads "Protected". A
-- resource that is an APFS volume (`volume` names its role) takes the
-- volume's own used space from `model.volumeUsage` instead of a walk.
function Inventory.plan()
	local model = Model.db
	local paths, ids, exclusions = {}, {}, {"/Volumes", "/dev", "/System/Volumes"}
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
		for _, relative in ipairs({"/Library/Photos", "/Library/Music", "/Library/MediaLibrary", "/Library/Containers/com.apple.Photos", "/Library/Containers/com.apple.Music", "/Library/Containers/com.apple.AMPArtworkAgent", "/Library/Group Containers/group.com.apple.Photos", "/Library/Group Containers/group.com.apple.Music"}) do
			table.insert(exclusions, model.home .. relative)
		end
	end
	return paths, ids, exclusions
end
-- The same walk that measures categories also ranks large files, totals file
-- extensions and lists each location's immediate children, so Large Files,
-- File Types and Applications never need a second pass over the disk.
Inventory.summary = {files = 500, minimumFileBytes = 50e6, oldDays = 365}
function Inventory.options(now)
	return {files = Inventory.summary.files, minimumFileBytes = Inventory.summary.minimumFileBytes,
		oldBefore = (now or os.time()) - Inventory.summary.oldDays * 86400, extensions = true, breakdown = true}
end
-- A refresh discards old values before any new result can become visible.
function Inventory.begin(ids)
	local model = Model.db
	model.scan = {running = true}
	model.files, model.breakdowns, model.folderSizes = nil, {}, nil
	for _, id in ipairs(ids) do model.measurements[id] = {status = "calculating"} end
end
function Inventory.cancel()
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
function Inventory.cloud()
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
function Inventory.progress(ids, result)
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
function Inventory.apply(ids, result)
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

return Inventory
