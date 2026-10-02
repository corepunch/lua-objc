-- The folder list: sample folders with measured, measuring and denied
-- sizes. It needs the settings, whose size threshold hides small folders, so
-- a changed setting makes this model stale.
local Model = require("data.model")

local Folders = Model.define({ id = "folders", schema = "Folders", needs = {"settings"} })

local SAMPLE = {
	{name = "Developer", icon = "hammer.fill", bytes = 56.4e9},
	{name = "Music", icon = "music.note", bytes = 21.1e9},
	{name = "Documents", icon = "doc.fill", bytes = 14.0e9},
	{name = "Downloads", icon = "arrow.down.circle.fill", bytes = 180e6},
	{name = "Library", icon = "books.vertical.fill", bytesState = "denied"},
	{name = "Caches", icon = "memorychip", bytesState = "calculating"},
}

function Folders.new(needs)
	return setmetatable({settings = needs.settings, measured = SAMPLE, canRescan = true, scans = 0}, Folders)
end

-- The folders at or above the settings' threshold; states always show.
function Folders:rows()
	local minimum, rows, largest = self.settings:minimumBytes(), {}, 0
	for _, folder in ipairs(self.measured) do largest = math.max(largest, folder.bytes or 0) end
	for _, folder in ipairs(self.measured) do
		if not folder.bytes or folder.bytes >= minimum then
			table.insert(rows, {name = folder.name, icon = folder.icon, bytes = folder.bytes, sizeState = folder.bytesState,
				relative = folder.bytes and largest > 0 and folder.bytes / largest or 0})
		end
	end
	return rows
end

function Folders:summary()
	local count = #self:rows()
	return string.format("%d folder%s", count, count == 1 and "" or "s") .. (self.scans > 0 and ", scanned " .. self.scans .. "×" or "")
end

function Folders:rescan()
	self.scans = self.scans + 1
end

return Folders
