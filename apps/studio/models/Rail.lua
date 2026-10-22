local Theme = require("apps.studio.models.Theme")
local Model = {}

-- Modes switch what the agent card shows; the rail highlights the one showing.
local MODES = {
	{ id = "chat", title = "Chat", icon = "bubble.left.and.bubble.right.fill", action = "showChat" },
	{ id = "code", title = "Code", icon = "chevron.left.forwardslash.chevron.right", action = "showCode" },
}

-- Project actions live on the rail, as Run and Source Control do in the
-- activity bar of VS Code: Run reloads the preview, Commit records the
-- project.
local ACTIONS = {
	{ id = "run", title = "Run", icon = "play.fill", action = "reloadPreview" },
	{ id = "commit", title = "Commit", icon = "point.3.connected.trianglepath.dotted", action = "commitProject" },
}

-- Workspace destinations follow. Projects are made from the toolbar's
-- project menu, so the rail holds only what is not about one project.
local DESTINATIONS = {
	{ id = "plugins", title = "Plugins", icon = "puzzlepiece.extension", action = "openPlugins" },
}

local FOOTER = {
	{ id = "settings", title = "Settings", icon = "gearshape", action = "openSettings" },
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
		actions = ACTIONS,
		destinations = DESTINATIONS,
		footer = FOOTER,
	}
end

return Model
