-- Capture plan for the Diskmap reel, run in one Diskmap launch on the
-- showcase disk (`--showcase`: the synthetic Mock HDD with presentable
-- names) by `make diskmap-reel-captures`:
--
--   ./lua-objc --capture-plan=reels/diskmap/capture.lua --width=1280 --height=800 \
--     apps/diskmap/init.lua --showcase
--
-- Every page the reel uses is captured in light and dark into captures/,
-- which is generated, not committed. "treemap" is the Map page drawn as
-- rectangles.
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local PAGES = { "overview", "map", "largest", "files", "kinds", "cleanup", "updates", "guide" }

return function(capture, app)
	for _, appearance in ipairs({ "light", "dark" }) do
		capture.appearance(appearance)
		for _, page in ipairs(PAGES) do
			app:show(page)
			capture.shot(here .. "captures/" .. page .. "-" .. appearance)
		end
		app:show("map")
		app:show("map", {style = "rectangles"})
		capture.shot(here .. "captures/treemap-" .. appearance)
		app:show("map", {style = "rings"})
	end
end
