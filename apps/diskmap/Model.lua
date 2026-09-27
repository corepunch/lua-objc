local Catalog = require("apps.diskmap.Catalog")
local Resources = require("apps.diskmap.models.Resources")
local Model = {}
function Model.size(bytes)
	if bytes == nil then return "Not measured" end
	if bytes >= 1e12 then return string.format("%.2f TB", bytes / 1e12) end
	if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
	if bytes >= 1e6 then return string.format("%.1f MB", bytes / 1e6) end
	return string.format("%.0f KB", bytes / 1000)
end
-- Counts with thousands separators, as Finder shows item counts.
-- Whole percentages, "<1%" for a sliver, so share labels stay one width
-- across every list.
function Model.percent(bytes, total)
	if not bytes or bytes <= 0 or not total or total <= 0 then return "" end
	local value = bytes * 100 / total
	if value < 1 then return "<1%" end
	return string.format("%d%%", math.floor(value + 0.5))
end

-- "1 app", "3 apps": `count` may already be a formatted number.
function Model.plural(count, word)
	return count .. " " .. word .. (tostring(count) == "1" and "" or "s")
end

-- "3 days ago", "5 months ago", "2 years ago": the precision a person needs
-- to decide whether something is still in use.
function Model.ago(days)
	local plural = Model.plural
	if days < 1 then return "Today" end
	if days < 2 then return "Yesterday" end
	if days < 31 then return days .. " days ago" end
	if days < 365 then return plural(math.floor(days / 30.4), "month") .. " ago" end
	return plural(math.floor(days / 365), "year") .. " ago"
end

function Model.count(value)
	local text = tostring(math.floor(value or 0))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (result:gsub("^,", ""))
end
function Model.new(home)
	-- `files` holds the last finished scan's large-file and extension
	-- summaries; `breakdowns` maps a resource id to its immediate children.
	local self = {home = home, includeMedia = false, measurements = {}, kept = {}, scan = {}, breakdowns = {}}
	local resources, err = Resources.new(self, Catalog.tree(home))
	assert(resources, err and err.message or "Could not build Diskmap resources")
	self.resources = resources
	for _, row in ipairs(resources:leaves()) do
		if row.mediaAccess then self.measurements[row.id] = {status = "excluded"} end
		if row.measurement then self.measurements[row.id] = {status = row.measurement} end
	end
	return self
end
function Model.total(model)
	local bytes = 0; for _, m in pairs(model.measurements) do bytes = bytes + (m.bytes or 0) end
	return bytes
end
return Model
