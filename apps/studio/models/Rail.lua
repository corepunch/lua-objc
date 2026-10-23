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

-- `selected` is the id of the mode the agent card opens in; `badges` maps
-- an action id to a count shown on its item (Commit: changed files), as
-- the activity bar of VS Code counts changes on Source Control.
function Model.presentation(selected, badges)
	selected = selected or MODES[1].id
	badges = badges or {}
	local modes = {}
	for _, mode in ipairs(MODES) do
		table.insert(modes, { id = mode.id, title = mode.title, icon = mode.icon, action = mode.action,
			selected = mode.id == selected })
	end
	local actions = {}
	for _, action in ipairs(ACTIONS) do
		local count = tonumber(badges[action.id]) or 0
		table.insert(actions, { id = action.id, title = action.title, icon = action.icon, action = action.action,
			badge = count > 0 and (count > 99 and "99+" or tostring(count)) or nil,
			label = count > 0 and (action.title .. ", " .. count .. (count == 1 and " change" or " changes")) or action.title })
	end
	return {
		tint = Theme.tint,
		brand = { title = "Lua Studio", icon = "hammer.fill", colors = Theme.brand },
		modes = modes,
		actions = actions,
		destinations = DESTINATIONS,
		footer = FOOTER,
	}
end

return Model
