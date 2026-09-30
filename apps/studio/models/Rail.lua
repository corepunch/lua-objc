local Theme = require("apps.studio.models.Theme")
local Model = {}

-- Modes switch what the agent card shows; selecting one moves the rail's
-- highlight. `mode` is the index the workspace's setMode action takes.
local MODES = {
	{ id = "chat", title = "Chat", icon = "bubble.left.and.bubble.right.fill", action = "showChat", mode = 0 },
	{ id = "code", title = "Code", icon = "chevron.left.forwardslash.chevron.right", action = "showCode", mode = 1 },
}

-- Workspace destinations live on the rail, as in an editor's activity bar,
-- so the project menu lists projects only.
local DESTINATIONS = {
	{ id = "templates", title = "Templates", icon = "square.grid.2x2" },
	{ id = "examples", title = "Examples", icon = "shippingbox" },
	{ id = "plugins", title = "Plugins", icon = "puzzlepiece.extension" },
}

local FOOTER = {
	{ id = "settings", title = "Settings", icon = "gearshape" },
}

-- `selected` is the id of the mode the agent card opens in.
function Model.presentation(selected)
	selected = selected or MODES[1].id
	local modes = {}
	for _, mode in ipairs(MODES) do
		table.insert(modes, { id = mode.id, title = mode.title, icon = mode.icon, action = mode.action,
			mode = mode.mode, selected = mode.id == selected })
	end
	return {
		tint = Theme.tint,
		brand = { title = "Lua Studio", icon = "hammer.fill", colors = Theme.brand },
		modes = modes,
		destinations = DESTINATIONS,
		footer = FOOTER,
	}
end

-- The id of the mode at `index`, as setMode receives it.
function Model.modeAt(index)
	for _, mode in ipairs(MODES) do
		if mode.mode == index then return mode.id end
	end
	return nil
end

return Model
