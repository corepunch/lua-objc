local Theme = require("apps.studio.helpers.Theme")
local Model = {}

-- The rail chooses what fills the column beside the agent card, as an
-- editor's activity bar chooses its side bar: the running app, the project
-- files, source control or the projects. The agent card stays put, so the
-- conversation is always beside whichever view the rail shows.
local PANELS = {
	{ id = "preview", title = "Preview", icon = "iphone" },
	{ id = "files", title = "Files", icon = "folder" },
	{ id = "git", title = "Source Control", icon = "point.3.connected.trianglepath.dotted" },
	{ id = "projects", title = "Projects", icon = "square.stack" },
}

-- Catalogs open as sheets; they are places to start from, not views to keep.
local DESTINATIONS = {
	{ id = "templates", action = "showTemplates", title = "Templates", icon = "square.grid.2x2" },
	{ id = "examples", action = "showExamples", title = "Examples", icon = "shippingbox" },
	{ id = "plugins", action = "showPlugins", title = "Plugins", icon = "puzzlepiece.extension" },
}

local FOOTER = {
	{ id = "settings", action = "showSettings", title = "Settings", icon = "gearshape" },
}

Model.panels = PANELS

-- The side column is just wide enough for an iPhone-proportioned device at
-- iPad height, and every view keeps that width so the card never moves; the
-- agent card receives every other point.
Model.columnWidth = 440

-- `selected` is the id of the panel the column shows.
function Model.presentation(selected)
	selected = selected or PANELS[1].id
	local panels = {}
	for _, panel in ipairs(PANELS) do
		table.insert(panels, { id = panel.id, title = panel.title, icon = panel.icon,
			action = "showPanel_" .. panel.id, selected = panel.id == selected })
	end
	return {
		tint = Theme.tint,
		brand = { title = "Lua Studio", icon = "hammer.fill", colors = Theme.brand },
		panels = panels,
		destinations = DESTINATIONS,
		footer = FOOTER,
	}
end

return Model
