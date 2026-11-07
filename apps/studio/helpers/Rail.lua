local Theme = require("apps.studio.helpers.Theme")
local Model = {}

-- Modes switch what the agent card shows; the rail highlights the one showing.
local MODES = {
	{ id = "chat", title = "Chat", icon = "bubble.left.and.bubble.right.fill", action = "showChat" },
	{ id = "code", title = "Code", icon = "chevron.left.forwardslash.chevron.right", action = "showCode" },
}

-- Workspace destinations live on the rail, as in an editor's activity bar,
-- so the project menu lists projects only.
local DESTINATIONS = {
	{ id = "github", action = "showGitHub", title = "GitHub", icon = "point.3.connected.trianglepath.dotted" },
	{ id = "templates", action = "showTemplates", title = "Templates", icon = "square.grid.2x2" },
	{ id = "examples", action = "showExamples", title = "Examples", icon = "shippingbox" },
	{ id = "plugins", action = "showPlugins", title = "Plugins", icon = "puzzlepiece.extension" },
}

local FOOTER = {
	{ id = "settings", action = "showSettings", title = "Settings", icon = "gearshape" },
}

-- `selected` is the id of the mode the agent card opens in.
function Model.presentation(selected)
	selected = selected or MODES[1].id
	local modes = {}
	for _, mode in ipairs(MODES) do
		table.insert(modes, { id = mode.id, title = mode.title, icon = mode.icon, action = mode.action,
			selected = mode.id == selected })
	end
	return {
		tint = Theme.tint,
		brand = { title = "Lua Studio", icon = "hammer.fill", colors = Theme.brand },
		modes = modes,
		destinations = DESTINATIONS,
		footer = FOOTER,
	}
end

return Model
