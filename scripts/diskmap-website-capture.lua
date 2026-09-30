-- Run from the repository root after creating build/diskmap-website:
-- ./lua-objc --capture-plan=scripts/diskmap-website-capture.lua \
--   --width=1280 --height=800 apps/diskmap/init.lua --showcase
-- Showcase uses synthetic data so published captures contain no personal files.
return function(capture, app)
	for _, shot in ipairs({
		{ page = "overview", appearance = "light" },
		{ page = "map", appearance = "dark" },
		{ page = "cleanup", appearance = "light" },
		{ page = "developer", appearance = "dark" },
	}) do
		capture.appearance(shot.appearance)
		app:show(shot.page)
		capture.shot("build/diskmap-website/" .. shot.page)
	end
end
