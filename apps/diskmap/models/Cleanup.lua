local Model = require("apps.diskmap.Model")
local Preferences = require("apps.diskmap.models.Preferences")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Cleanup = {}
function Cleanup.suggestions(model, rules)
	local result = {}
	for _, row in ipairs(model.leaves) do
		local m, rule = model.measurements[row.id], (rules or Rules)[row.id]
		if not rule and (row.reviewThreshold or row.agent or row.id == "opencode-downloads" or row.id == "grok-support") then
			rule = {threshold = row.reviewThreshold or 100e6, priority = 3, advice = row.consequence or row.subtitle}
		end
		if rule and m and (m.status == "complete" or m.status == "partial") and (m.bytes or 0) >= rule.threshold
			and not Preferences.isKept(model, row.id) and row.policy ~= "Essential" then
			local value = {}; for k, v in pairs(row) do value[k] = v end
			value.bytes, value.size = m.bytes, (m.status == "partial" and "≥ " or "") .. Model.size(m.bytes)
			value.partial = m.status == "partial"
			value.impact = row.policy == "Rebuildable" and not value.partial and "Safe/rebuildable" or "Needs review"
			value.priority, value.threshold = rule.priority, rule.threshold
			value.subtitle = rule.advice
			value.evidence = "Measured " .. value.size .. " · Review threshold " .. Model.size(rule.threshold)
			result[#result + 1] = value
		end
	end
	table.sort(result, function(a, b)
		if a.priority ~= b.priority then return a.priority < b.priority end
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.id < b.id
	end)
	return result
end
return Cleanup
