-- The window toolbar: the project menu and the status line lead, the chat
-- toggle trails. Run and Commit are on the rail, as in an activity bar;
-- the stage keeps only the device and the agent card only the agent. The
-- menu lists the projects, the icon choices and New Project.
local Theme = require("apps.studio.models.Theme")
local Model = {}

local DESTINATIONS = {
	{ title = "New Project", icon = "plus", action = "newProject" },
}

function Model.presentation(projects, iconChoices)
	projects = projects or {}
	local current = projects[1]
	for _, project in ipairs(projects) do
		if project.selected then current = project; break end
	end
	return {
		project = current or { title = "No Project", icon = "app.dashed" },
		projects = projects,
		iconChoices = iconChoices or {},
		destinations = DESTINATIONS,
		status = "Ready",
		-- The activity viewer's symbol follows the tone of the status, as
		-- Xcode's shows a warning or a success mark: "ok" or "problem".
		tone = "ok",
		busy = false,
		chatHidden = false,
		tint = Theme.tint,
	}
end

return Model
