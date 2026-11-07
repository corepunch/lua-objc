local Theme = require("apps.studio.helpers.Theme")
local Model = {}

-- Just wide enough for an iPhone-proportioned device at iPad height and for
-- the stage bar; the chat receives every other point.
local STAGE_WIDTH = 440

-- The project menu lists the projects, then what makes another one. The
-- other workspace destinations are on the activity rail.
local DESTINATIONS = {
	{ title = "GitHub", action = "showGitHub", icon = "point.3.connected.trianglepath.dotted" },
	{ title = "New Project", action = "newProject", icon = "plus" },
	{ title = "Delete Project…", action = "showDeleteProject", icon = "trash" },
}

function Model.presentation(projects, iconChoices)
	projects = projects or {}
	local current = projects[1]
	for _, project in ipairs(projects) do
		if project.selected then current = project; break end
	end
	return {
		project = current or { title = "No Project", icon = "rocket.fill" },
		projects = projects,
		iconChoices = iconChoices or {},
		destinations = DESTINATIONS,
		device = "iPhone 16",
		zoom = "100%",
		runLabel = "Run",
		status = "Ready",
		stageWidth = STAGE_WIDTH,
		tint = Theme.tint,
	}
end

return Model
