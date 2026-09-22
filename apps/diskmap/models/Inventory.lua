local Catalog = require("apps.diskmap.Catalog")
local Inventory = {}
-- Always use one complete batch: hard links must keep a single owner across refreshes.
function Inventory.plan(model)
	local paths, ids, exclusions = {}, {}, {"/Volumes", "/dev", "/System/Volumes"}
	for _, row in ipairs(model.leaves) do
		if row.path then
			paths[#paths + 1] = row.path; ids[#ids + 1] = row.id
			exclusions[#exclusions + 1] = row.path
		end
	end
	return paths, ids, exclusions
end
function Inventory.apply(model, ids, result)
	model.scan = {completedAt = os.time(), errors = result.errors or 0, visited = result.visited or 0, seconds = result.seconds or 0, issues = result.issues or {}, failure = result.failure}
	for i, id in ipairs(ids) do
		local node = result.trees and result.trees[i]
		local state = result.rootStates and result.rootStates[i]
		if result.failure and result.failure ~= "" and not state then
			local old = model.measurements[id] or {}; old.status = "stale"; model.measurements[id] = old
		else
			model.measurements[id] = {bytes = type(node) == "table" and node.kb * 1024 or state == "missing" and 0 or nil,
				status = state == "skipped" and "skipped" or state == "missing" and "complete" or type(node) == "table" and (node.partial and "partial" or "complete") or "denied"}
		end
	end
end

function Inventory.snapshot(model, disk)
	return {version = Catalog.version, measurements = model.measurements, disk = disk, scan = model.scan}
end
function Inventory.restore(model, data)
	for id, m in pairs(data.measurements) do
		if model.byId[id] and not model.byId[id].children then model.measurements[id] = m end
	end
	model.scan = data.scan or {}
end
return Inventory
