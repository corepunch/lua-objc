local Model = require("apps.diskmap.Model")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Cleanup = {}
-- Build folders are judged per ecosystem, not per folder: sixty 200 MB
-- node_modules folders are 12 GB that no single folder's threshold would
-- ever show. A group is one suggestion once its measured, unkept folders
-- reach this total; it is Rebuildable only when every one of them is.
Cleanup.buildGroupThreshold = 500e6
local function buildGroups(model)
	local groups, order = {}, {}
	for _, row in ipairs(model.resources:leaves()) do
		local parent = row.artifact and row:getParent()
		local m = model.measurements[row.id]
		if parent and parent.id:match("^build%-") and not row:isKept() and m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) > 0 then
			local group = groups[parent.id]
			if not group then
				group = {row = parent, bytes = 0, projects = {}, count = 0, partial = false, rebuildable = true}
				groups[parent.id] = group
				table.insert(order, parent.id)
			end
			group.bytes = group.bytes + m.bytes
			group.partial = group.partial or m.status == "partial"
			group.rebuildable = group.rebuildable and row.policy == "Rebuildable"
			if not group.projects[row.project or row.path] then group.projects[row.project or row.path] = true; group.count = group.count + 1 end
		end
	end
	local result = {}
	for _, id in ipairs(order) do table.insert(result, groups[id]) end
	return result
end
Cleanup.buildGroups = buildGroups

function Cleanup.suggestions(model, rules)
	local result = {}
	for _, group in ipairs(buildGroups(model)) do
		local row = group.row
		if group.bytes >= Cleanup.buildGroupThreshold and not row:isKept() then
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, group = true, projects = group.count,
				bytes = group.bytes,
				policy = group.rebuildable and "Rebuildable" or "Review"}
			Model.sizeLabel(value, group.partial and "partial" or "complete", group.bytes)
			value.impact = group.rebuildable and not group.partial and "Safe/rebuildable" or "Needs review"
			value.priority, value.threshold = 2, Cleanup.buildGroupThreshold
			value.subtitle = (row.subtitle or "") .. " In " .. Model.plural(group.count, "project") .. "."
			value.evidence = "Measured " .. value.size .. " in " .. Model.plural(group.count, "project")
			table.insert(result, value)
		end
	end
	for _, row in ipairs(model.resources:leaves()) do
		local m, rule = model.measurements[row.id], (rules or Rules)[row.id]
		if row.artifact then m = nil end
		if not rule and (row.reviewThreshold or row.agent or row.id == "opencode-downloads" or row.id == "grok-support") then
			rule = {threshold = row.reviewThreshold or 100e6, priority = 3, advice = row.consequence or row.subtitle}
		end
		if rule and m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) >= rule.threshold
			and not row:isKept() and row.policy ~= "Essential" then
			local value = {id = row.id, name = row.name, path = row.path, policy = row.policy, action = row.action,
				subtitle = row.subtitle, consequence = row.consequence, icon = row.icon, color = row.color, appIcon = row.appIcon}
			value.bytes = m.bytes
			Model.sizeLabel(value, m.status, m.bytes)
			value.impact = row.policy == "Rebuildable" and not value.partial and "Safe/rebuildable" or "Needs review"
			value.priority, value.threshold = rule.priority, rule.threshold
			value.subtitle = rule.advice
			value.evidence = "Measured " .. value.size .. " · Review threshold " .. Model.size(rule.threshold)
			table.insert(result, value)
		end
	end
	table.sort(result, function(a, b)
		if a.priority ~= b.priority then return a.priority < b.priority end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	return result
end
function Cleanup.moveToTrash(model, id, service)
	local row = model.resources:find(id)
	if not row then return false, {code = "unknown_resource", message = "Resource is not registered."} end
	local valid, validation = row:validateTrash()
	if not valid then return false, validation end
	local ok, result, message = pcall(function() return service.trash(row.path) end)
	if not ok then return false, {code = "trash_service", message = tostring(result)} end
	if not result then return false, {code = "trash_service", message = message or "Check permissions."} end
	return true
end
function Cleanup.emptyTrash(model, id, service)
	local row = model.resources:find(id)
	if not row then return false, {code = "unknown_resource", message = "Resource is not registered."} end
	local valid, validation = row:validateEmpty()
	if not valid then return false, validation end
	local ok, result, message = pcall(function() return service.emptyTrash() end)
	if not ok then return false, {code = "empty_service", message = tostring(result)} end
	if not result then return false, {code = "empty_service", message = message or "Check permissions."} end
	return true
end
return Cleanup
