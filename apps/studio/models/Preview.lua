local Model = {}

-- Just wide enough for an iPhone-proportioned device at iPad height and for
-- the stage bar; the chat receives every other point.
local STAGE_WIDTH = 440

-- Workspace destinations share the project menu with the project list, so no
-- navigation sidebar takes width from the preview and chat.
local DESTINATIONS = {
	{ title = "New Project", icon = "plus" },
	{ title = "Templates", icon = "square.grid.2x2" },
	{ title = "Examples", icon = "shippingbox" },
	{ title = "Plugins", icon = "puzzlepiece" },
	{ title = "Settings", icon = "gearshape" },
}

function Model.presentation(projects)
	projects = projects or {}
	local current = projects[1]
	for _, project in ipairs(projects) do
		if project.selected then current = project; break end
	end
	return {
		project = current or { title = "No Project", icon = "app.dashed" },
		projects = projects,
		destinations = DESTINATIONS,
		device = "iPhone 16",
		zoom = "100%",
		runLabel = "Run",
		status = "Ready",
		stageWidth = STAGE_WIDTH,
	}
end

return Model
