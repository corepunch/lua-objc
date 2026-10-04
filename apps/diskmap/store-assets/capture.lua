-- Capture plan for the Mac App Store screenshots, run on the showcase disk
-- by `make diskmap-store-screenshots`:
--
--   ./lua-objc --capture-plan=apps/diskmap/store-assets/capture.lua --width=1280 --height=800 \
--     apps/diskmap/init.lua --showcase
--
-- App Store Connect accepts Mac screenshots of 1280 × 800, 1440 × 900,
-- 2560 × 1600 or 2880 × 1800 pixels and rejects any other size. A capture
-- is the window's content at backing scale, so a 1280 × 800 window gives
-- 2560 × 1600. The Make target then flattens each PNG to JPEG, since App
-- Store Connect refuses transparency; tests/diskmap_store_assets.test.lua
-- checks every file.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SHOTS = { "overview", "map", "largest", "cleanup", "kinds", "developer" }

return function(capture, app)
	capture.appearance("dark")
	for i, page in ipairs(SHOTS) do
		app:show(page)
		local prefix = string.format("%sen/screenshots/%02d-%s", here, i, page)
		capture.shot(prefix)
		-- Only the picture is an asset; the layout dump is for reels and tools.
		os.remove(prefix .. ".layout.xml")
	end
end
