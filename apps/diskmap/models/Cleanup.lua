local Model = require("apps.diskmap.Model")
local Preferences = require("apps.diskmap.models.Preferences")
local Rules = require("apps.diskmap.knowledge.CleanupRules")
local Cleanup = {}
function Cleanup.suggestions(model, rules)
	local result = {}
	for _, row in ipairs(model.leaves) do
		local m, rule = model.measurements[row.id], (rules or Rules)[row.id]
		if rule and m and m.status == "complete" and (m.bytes or 0) >= rule.threshold
			and not Preferences.isKept(model, row.id) and row.policy ~= "System managed" then
			local value = {}; for k, v in pairs(row) do value[k] = v end
			value.bytes, value.size = m.bytes, Model.size(m.bytes)
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
