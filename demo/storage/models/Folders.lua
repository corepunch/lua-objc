-- The folder list: sample folders with measured, measuring and denied
-- sizes. It needs the settings, whose size threshold hides small folders.
local Model = require("data.model")

local Folders = Model.define({id = "folders", needs = {"settings"}})

local SAMPLE = {
	{name = "Developer", icon = "hammer.fill", bytes = 56.4e9},
	{name = "Music", icon = "music.note", bytes = 21.1e9},
	{name = "Documents", icon = "doc.fill", bytes = 14.0e9},
	{name = "Downloads", icon = "arrow.down.circle.fill", bytes = 180e6},
	{name = "Library", icon = "books.vertical.fill", denied = true},
	{name = "Caches", icon = "memorychip", calculating = true},
}

local function size(bytes)
	if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
	return string.format("%.0f MB", bytes / 1e6)
end

function Folders.new(needs)
	return setmetatable({settings = needs.settings, scans = 0}, Folders)
end

-- The folders at or above the settings' threshold; unmeasured ones always show.
function Folders:rows()
	local minimum, rows, largest = self.settings:minimumBytes(), {}, 0
	for _, folder in ipairs(SAMPLE) do largest = math.max(largest, folder.bytes or 0) end
	for _, folder in ipairs(SAMPLE) do
		if not folder.bytes or folder.bytes >= minimum then
			table.insert(rows, {
				name = folder.name, icon = folder.icon, calculating = folder.calculating,
				size = folder.bytes and size(folder.bytes) or folder.denied and "No access" or "Calculating…",
				sizeIcon = folder.denied and "lock.fill" or nil, sizeColor = folder.denied and "systemOrange" or nil,
				relative = folder.bytes and folder.bytes / largest or nil,
			})
		end
	end
	return rows
end

-- What views/Folders.etlua reads.
function Folders:data()
	local rows = self:rows()
	return {lists = {folders = rows}, summary = string.format("%d folder%s", #rows, #rows == 1 and "" or "s")
		.. (self.scans > 0 and ", scanned " .. self.scans .. "×" or "")}
end

function Folders:rescan()
	self.scans = self.scans + 1
end

return Folders
