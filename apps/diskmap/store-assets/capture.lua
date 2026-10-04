-- Native source captures for the five store artboards. Layout dumps stay in
-- build/ so the exported composition can be checked against the actual UI.
-- Showcase never scans personal files or changes the user's stored choices.
local SHOTS = {
	{ page = "map", appearance = "dark" },
	{ page = "cleanup", appearance = "light" },
	{ page = "files", appearance = "dark" },
	{ page = "kinds", appearance = "light" },
	{ page = "developer", appearance = "dark" },
}

return function(capture, app)
	for _, shot in ipairs(SHOTS) do
		capture.appearance(shot.appearance)
		app:show(shot.page)
		capture.shot("build/diskmap-store/" .. shot.page)
	end
end
