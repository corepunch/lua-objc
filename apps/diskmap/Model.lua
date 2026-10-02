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
-- Measurement states that stand in for a size: a short word, and the
-- symbol and colour the size meter draws before it, where the spinner sits
-- while measuring. Warnings are orange, failures red; states that are
-- expected are neutral.
Model.sizeStates = {
	denied = {text = "No access", icon = "lock.fill", color = "systemOrange"},
	protected = {text = "Protected", icon = "lock.shield.fill", color = "systemGray"},
	excluded = {text = "Not scanned", icon = "minus.circle.fill", color = "systemGray"},
	skipped = {text = "Linked", icon = "link.circle.fill", color = "systemTeal"},
	unsupported = {text = "System Managed", icon = "gearshape.fill", color = "systemBlue"},
	failed = {text = "Unavailable", icon = "exclamationmark.triangle.fill", color = "systemRed"},
}

-- A size that may be a lower bound: a partial measurement could not read
-- some items, so it reads "≥".
function Model.atLeast(bytes, partial)
	return (partial and "≥ " or "") .. Model.size(bytes)
end

-- Fills a row's size meter from a measurement status.
function Model.sizeLabel(row, status, bytes)
	local state = Model.sizeStates[status]
	row.calculating = status == "calculating"
	row.partial = status == "partial"
	row.size = state and state.text or row.calculating and "Calculating…" or Model.atLeast(bytes, row.partial)
	row.sizeIcon, row.sizeColor = state and state.icon, state and state.color
	return row
end

-- Counts with thousands separators, as Finder shows item counts.
-- Whole percentages, "<1%" for a sliver, so share labels stay one width
-- across every list.
-- A measured zero is "0%", so empty rows keep the same label-and-bar layout
-- as the rest; only an unmeasured size has no share.
function Model.percent(bytes, total)
	if not bytes or bytes < 0 or not total or total <= 0 then return "" end
	if bytes == 0 then return "0%" end
	local value = bytes * 100 / total
	if value < 1 then return "<1%" end
	return string.format("%d%%", math.floor(value + 0.5))
end

-- A path as it is shown: from the home folder, "~/Developer/app".
function Model.tilde(path, home)
	if path and home and home ~= "" and path:sub(1, #home + 1) == home .. "/" then return "~" .. path:sub(#home + 1) end
	return path
end

-- "1 app", "3 apps": `count` may already be a formatted number.
function Model.plural(count, word)
	if tonumber(count) == 1 then return count .. " " .. word end
	local stem, noun = word:match("^(.-)([%a]+)$")
	if not noun then return count .. " " .. word .. "s" end
	local lower, plural = noun:lower(), noun .. "s"
	local irregular = {person = "people", child = "children", analysis = "analyses"}
	if irregular[lower] then
		plural = irregular[lower]
		if noun:match("^%u") then plural = plural:sub(1, 1):upper() .. plural:sub(2) end
	elseif lower:match("[^aeiou]y$") then plural = noun:sub(1, -2) .. "ies"
	elseif lower:match("[sxz]$") or lower:match("ch$") or lower:match("sh$") then plural = noun .. "es" end
	return count .. " " .. stem .. plural
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

-- Lists have no column headers, so a relative age names its event.
function Model.used(age)
	if age == "—" then return age end
	if age == "Unknown" then return "Last use unknown" end
	return "Used " .. age:lower()
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
