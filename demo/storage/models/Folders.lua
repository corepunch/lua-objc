-- The folders: measured, measuring and denied sizes. The settings' size
-- threshold hides small folders.
local Model = require("data.model")
local Settings = require("demo.storage.models.Settings")

local Folders, Folder = Model:extend("folders", {primaryKey = "name"})

-- The folders at or above the threshold (unmeasured ones always show), as
-- the rows the list draws.
function Folders:visible()
	local minimum = Settings:current():minimumBytes()
	local largest = 0
	for _, folder in ipairs(self:all()) do largest = math.max(largest, folder.bytes or 0) end
	return self:select(function(folder) return not folder.bytes or folder.bytes >= minimum end, {fields = {
		"name", "icon", "calculating", size = "sizeText",
		sizeIcon = function(folder) return folder.denied and "lock.fill" or nil end,
		sizeColor = function(folder) return folder.denied and "systemOrange" or nil end,
		relative = function(folder) return folder.bytes and folder.bytes / largest or nil end,
	}})
end

function Folder:sizeText()
	if self.bytes then
		if self.bytes >= 1e9 then return string.format("%.1f GB", self.bytes / 1e9) end
		return string.format("%.0f MB", self.bytes / 1e6)
	end
	return self.denied and "No access" or "Calculating…"
end

return Folders
