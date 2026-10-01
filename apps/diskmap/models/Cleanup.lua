local Model = require("apps.diskmap.Model")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Xcode = require("apps.diskmap.models.Xcode")
local Cleanup = {}

-- A suggestion carries three separate numbers. `bytes` is the measured size
-- of the location (what there is to review); `eligibleBytes` is what the
-- suggestion could actually recover once every child is checked (nil when
-- that cannot be known); the score ranks by eligible bytes, how sure we are
-- and how much work the owner's flow takes.
Cleanup.confidence = {High = 1, Medium = 0.6, Low = 0.3}
Cleanup.effort = {Low = 1, Medium = 1.5, High = 2.5}
-- Bytes to review with no eligibility proof count for this much of their size.
Cleanup.reviewFraction = 0.2
local SUPPORT_PLATFORMS = {devices = "iOS", ["watch-devices"] = "watchOS"}

-- {eligibleBytes | nil, confidence, reason | nil} for a measured resource.
-- A group agrees with its children: device support that holds only the newest
-- kept version offers nothing, and simulators offer only what the minimal
-- device set (published by the Simulators page) would remove.
function Cleanup.eligibility(model, row, measurement)
	local platform = SUPPORT_PLATFORMS[row.id]
	local children = platform and model.breakdowns[row.id]
	if children then
		local entries = {}
		for _, child in ipairs(children) do
			if child.directory then
				table.insert(entries, {platform = platform, name = child.name, path = child.name, bytes = math.floor((child.kb or 0) * 1024 + 0.5)})
			end
		end
		local older = Xcode.total(Xcode.supportRows(entries), function(item) return not item.keep end)
		return older, "Medium", older == 0 and "Only the newest version is present, and it is kept." or nil
	end
	-- A tool's worktree folder is reviewed worktree by worktree, so its total is
	-- not also a suggestion once that review exists.
	if row.page == "worktrees" and model.worktreePlan then
		return 0, "Medium", "Reviewed worktree by worktree on the Worktrees page."
	end
	if row.id == "simulators" and model.simulatorPlan then
		local plan = model.simulatorPlan
		return plan.removalBytes, "Medium", plan.removalBytes == 0 and "The minimal device set has nothing eligible to remove." or nil
	end
	if row.policy == "Rebuildable" then return measurement.bytes, "High" end
	return nil, "Low"
end

local function effortOf(row, rule)
	if rule and rule.effort then return rule.effort end
	if row.action == "trash" or row.action == "ownerCleanup" then return "Low" end
	if row.page then return "Medium" end
	return "High"
end

function Cleanup.score(value)
	local base = value.eligibleBytes or (value.bytes * Cleanup.reviewFraction)
	return base * Cleanup.confidence[value.confidence] / Cleanup.effort[value.effort]
end
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

-- Why a measured location is not a suggestion, by id; rebuilt on every call.
Cleanup.ineligible = {}
function Cleanup.suggestions(model, rules)
	local result = {}
	Cleanup.ineligible = {}
	for _, group in ipairs(buildGroups(model)) do
		local row = group.row
		if group.bytes >= Cleanup.buildGroupThreshold and not row:isKept() then
			local value = {id = row.id, name = row.name, icon = row.icon, color = row.color, group = true, projects = group.count,
				bytes = group.bytes,
				policy = group.rebuildable and "Rebuildable" or "Review"}
			Model.sizeLabel(value, group.partial and "partial" or "complete", group.bytes)
			value.impact = group.rebuildable and not group.partial and "Safe/rebuildable" or "Needs review"
			value.priority, value.threshold = 2, Cleanup.buildGroupThreshold
			value.eligibleBytes, value.confidence, value.effort = group.rebuildable and not group.partial and group.bytes or nil,
				group.rebuildable and "High" or "Low", "Low"
			value.kind = group.rebuildable and not group.partial and "rebuildable" or "decision"
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
			local eligible, confidence, reason = Cleanup.eligibility(model, row, m)
			value.eligibleBytes, value.confidence, value.effort = eligible, confidence, effortOf(row, rule)
			value.kind = value.impact == "Safe/rebuildable" and "rebuildable" or "decision"
			if eligible and eligible ~= m.bytes then
				value.evidence = value.evidence .. " · " .. Model.size(eligible) .. " eligible after keeping what is current"
			end
			if reason then
				-- Nothing to do here: the page says why instead of sending the reader
				-- to a destination with no candidate.
				Cleanup.ineligible[row.id] = reason
			else
				table.insert(result, value)
			end
		end
	end
	for _, value in ipairs(result) do value.score = Cleanup.score(value) end
	table.sort(result, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
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
