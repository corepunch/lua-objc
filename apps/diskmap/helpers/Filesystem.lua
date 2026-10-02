local Format = require("apps.diskmap.helpers.Format")
local Map = require("apps.diskmap.knowledge.Filesystem")
local Filesystem = {}

-- The macOS Folders page: every location in knowledge/Filesystem with what
-- it holds and what it takes on this Mac. A location's size comes from the
-- first source that has one: its APFS volume, the catalog resource that
-- measures it, or the page's own measurement of its path (`sizes`, keyed by
-- path, {bytes, state}). Locations no app can read say so instead of a size.

local STATES = {
	protected = {text = "Not readable", icon = "lock.shield.fill", color = "systemGray"},
	privacy = {text = "No access", icon = "lock.fill", color = "systemOrange"},
	missing = {text = "Not on this Mac", icon = "minus.circle", color = "tertiary"},
	unmeasured = {text = "Not measured", icon = "minus.circle", color = "tertiary"},
}

local function expand(path, home)
	return (path:gsub("^~", home or "~"))
end

-- Paths the page measures itself: readable locations that neither a volume
-- nor a catalog resource sizes. `facts` is what the store knows
-- (Categories:facts()): {home, volumeUsage, measured(id)}.
function Filesystem.pending(facts)
	local paths = {}
	for _, area in ipairs(Map.areas) do
		for _, location in ipairs(area.locations) do
			local guarded = location.guard == "sip" or location.guard == "owner"
			local leftover = location.leftover and facts.measured(location.leftover.id)
			if not guarded and not location.volume and not location.resource and not leftover then
				table.insert(paths, expand(location.path, facts.home))
			end
		end
	end
	return paths
end

local function sized(row, bytes, partial)
	row.bytes, row.size, row.partial = bytes, Format.atLeast(bytes, partial), partial
end

-- One location as a page row.
function Filesystem.row(location, sizes, fullDiskAccess, facts)
	local path = expand(location.path, facts.home)
	local guard = location.guard and Map.guards[location.guard]
	local row = {id = location.path, name = location.name, path = path, what = location.what,
		guardTitle = guard and guard.title or nil, resource = location.resource or (location.leftover and location.leftover.id)}
	local state
	if location.guard == "sip" or location.guard == "owner" then
		state = "protected"
	elseif location.volume and facts.volumeUsage and facts.volumeUsage[location.volume] then
		sized(row, facts.volumeUsage[location.volume], false)
	elseif location.volume and not row.resource then
		-- Only APFS can size a whole volume; walking / would count the disk twice.
		state = "unmeasured"
	elseif row.resource and facts.measured(row.resource) then
		local measured = facts.measured(row.resource)
		if measured.bytes then sized(row, measured.bytes, measured.status == "partial")
		elseif measured.status == "denied" then state = "privacy"
		elseif measured.status == "protected" then state = "protected"
		else state = "unmeasured" end
	else
		local entry = sizes and sizes[path]
		if not entry then state = "unmeasured"
		elseif entry.state == "missing" then state = "missing"
		elseif entry.state == "unreadable" and (entry.bytes or 0) == 0 then
			state = fullDiskAccess == true and "protected" or "privacy"
		else sized(row, entry.bytes or 0, entry.state == "unreadable") end
	end
	if state then
		local look = STATES[state]
		row.size, row.stateIcon, row.stateColor = look.text, look.icon, look.color
		row.state = state
	end
	-- The one-line status a reader sees before the explanation.
	row.status = row.guardTitle or (location.volume and ("APFS volume · " .. location.volume))
		or (location.leftover and "Leftovers collect here") or (location.expected and "On every Mac") or nil
	return row
end

-- Areas matching `query` with their rows, in map order.
function Filesystem.presentation(sizes, fullDiskAccess, query, facts)
	local needle = (query or ""):lower()
	local areas, count = {}, 0
	for _, area in ipairs(Map.areas) do
		local rows = {}
		local areaMatches = needle == "" or area.title:lower():find(needle, 1, true) ~= nil
		for _, location in ipairs(area.locations) do
			local text = (location.name .. " " .. location.path .. " " .. location.what):lower()
			if areaMatches or text:find(needle, 1, true) then
				table.insert(rows, Filesystem.row(location, sizes, fullDiskAccess, facts))
			end
		end
		if #rows > 0 then
			count = count + #rows
			table.insert(areas, {id = area.id, title = area.title, icon = area.icon, summary = area.summary, rows = rows})
		end
	end
	return {areas = areas, count = count, empty = count == 0}
end

return Filesystem
