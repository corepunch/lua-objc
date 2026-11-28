local CharacterSetup = {}

function CharacterSetup.groups(hero)
	local buckets = { abilities = {}, powers = {}, resources = {}, stats = {} }
	for _, row in ipairs(hero and hero.rows or {}) do
		local bucket = buckets[row.group] or buckets.stats
		local value = tostring(row.value)
		if row.maximum and row.maximum > 0 then
			value = value .. " / " .. row.maximum
		end
		table.insert(bucket, {
			label = row.label,
			value = row.rankLabel and row.rankLabel ~= "" and row.rankLabel .. " · " .. value or value,
		})
	end
	local groups = {}
	for _, key in ipairs({ "abilities", "powers", "resources", "stats" }) do
		if #buckets[key] > 0 then table.insert(groups, { key = key, rows = buckets[key] }) end
	end
	return groups
end

return CharacterSetup
