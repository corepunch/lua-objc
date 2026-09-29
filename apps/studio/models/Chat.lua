local Model = {}

-- Templates get a code symbol and Lua modules a document symbol. Each row
-- shows the file name, with its folder beneath it rather than the full path.
local ICONS = { etlua = "chevron.left.forwardslash.chevron.right", lua = "doc.text" }

local CHANGES = {
	{ path = "init.lua", added = 3 },
	{ path = "Model.lua", added = 86 },
	{ path = "Controller.lua", added = 54 },
	{ path = "views/Today.etlua", added = 41 },
	{ path = "views/Stats.etlua", added = 37 },
	{ path = "views/Settings.etlua", added = 22 },
}

function Model.changes(list)
	local result, added = {}, 0
	for _, change in ipairs(list) do
		added = added + change.added
		table.insert(result, {
			path = change.path,
			name = change.path:match("[^/]+$"),
			folder = change.path:match("^(.+)/[^/]+$") or "",
			icon = ICONS[change.path:match("%.(%w+)$")] or "doc",
			delta = "+" .. change.added,
		})
	end
	local noun = #result == 1 and "file" or "files"
	return result, { title = #result .. " " .. noun .. " changed", delta = "+" .. added }
end

function Model.presentation()
	local changes, summary = Model.changes(CHANGES)
	return {
		agent = { name = "Assistant", model = "openrouter/free" },
		modes = { "Chat", "Code" },
		prompt = "Create a simple habit tracker app like this. Use a clean modern design with a nice illustration. It should store data locally and have 3 tabs: Today, Stats, Settings.",
		response = "I’ll create a habit tracker with a clean design, local storage, and the three tabs you asked for. I’ll set up the project structure, then implement each screen.",
		changes = changes,
		changeSummary = summary,
		conclusion = "The app is ready and running in the preview. Habits and progress are saved locally.",
		suggestions = {
			{ title = "Add a feature", icon = "plus" },
			{ title = "Fix a bug", icon = "ladybug" },
			{ title = "Polish the UI", icon = "wand.and.stars" },
		},
	}
end

return Model
