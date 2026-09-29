-- Prints the level every patch of the library should have to sit at its
-- role's target (models/Calibration.lua). Run after designing or changing a
-- patch, and copy its level into library/Patches.lua:
--   ./lua-objc apps/dnb/library/calibrate.lua
_G.__headless = true
local Calibration = require("apps.dnb.models.Calibration")
local Library = require("apps.dnb.host.Library")

local patches = {}
for _, patch in pairs(Library.shared().patches) do table.insert(patches, patch) end
table.sort(patches, function(a, b) return a.id < b.id end)
for _, patch in ipairs(patches) do
	print(string.format("%-18s level = %.3g   (now %.3g, %+.1f dB)", patch.id, Calibration.level(patch), patch.level,
		Calibration.offset(patch)))
end
os.exit(0)
