local Inventory = {}
-- Always use one complete batch: hard links must keep a single owner across refreshes.
function Inventory.plan(model)
	local paths, ids, exclusions = {}, {}, {"/Volumes", "/dev", "/System/Volumes"}
	for _, row in ipairs(model.resources:leaves()) do
		if row.path then
			if not row.mediaAccess or model.includeMedia then
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
function Inventory.begin(model, ids)
	model.scan = {}
	model.files, model.breakdowns = nil, {}
	for _, id in ipairs(ids) do model.measurements[id] = {status = "calculating"} end
end
function Inventory.cancel(model)
	for id, m in pairs(model.measurements) do
		m.currentScan = nil
		if m.status == "calculating" then model.measurements[id] = {status = "notMeasured"} end
	end
end
local function measurement(node, state)
	return {bytes = type(node) == "table" and node.kb * 1024 or state == "missing" and 0 or nil,
		status = state == "skipped" and "skipped" or state == "missing" and "complete" or type(node) == "table" and (node.partial and "partial" or "complete") or "denied"}
end
function Inventory.progress(model, ids, result)
	model.scan = {errors = result.errors or 0, visited = result.visited or 0,
		completed = result.completed or 0, total = result.total or #ids, seconds = result.seconds or 0}
	for i = 1, math.min(result.completed or 0, #ids) do
		local state = result.rootStates and result.rootStates[i]
		if state then
			model.measurements[ids[i]] = measurement(result.trees and result.trees[i], state)
			model.measurements[ids[i]].currentScan = true
		end
	end
end
function Inventory.apply(model, ids, result)
	model.scan = {completedAt = os.time(), errors = result.errors or 0, visited = result.visited or 0, seconds = result.seconds or 0, issues = result.issues or {}, failure = result.failure}
	-- Summaries arrive only with a finished batch; a cancelled scan has none.
	if result.largeFiles or result.extensions then
		model.files = {large = result.largeFiles or {}, old = result.oldFiles or {}, extensions = result.extensions or {},
			oldBytes = result.oldBytes or 0, oldCount = result.oldCount or 0, partial = result.partial == true}
	end
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
