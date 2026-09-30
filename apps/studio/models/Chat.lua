local Model = {}
local Code = require("apps.studio.models.Code")
local Theme = require("apps.studio.models.Theme")

-- Templates get a code symbol and Lua modules a document symbol. Each row
-- shows the file name, with its folder beneath it rather than the full path.
local ICONS = { etlua = "chevron.left.forwardslash.chevron.right", lua = "doc.text" }

local CHANGES = {
	{ path = "init.lua", added = 3 },
	{ path = "Model.lua", added = 86 },
	{ path = "Controller.lua", added = 54 },
	{ path = "views/Window.etlua", added = 48 },
	{ path = "views/Today.etlua", added = 41 },
	{ path = "views/Stats.etlua", added = 37 },
	{ path = "views/Settings.etlua", added = 22 },
}

-- The starter conversation: a request, the agent's answer with the files it
-- created, and its note that the app is running.
Model.DEFAULT = {
	messages = {
		{ role = "user", text = "Create a simple habit tracker app like this. Use a clean modern design with a nice illustration. It should store data locally and have 3 tabs: Today, Stats, Settings." },
		{ role = "agent", text = "I’ll create a habit tracker with a clean design, local storage, and the three tabs you asked for. I’ll set up the project structure, then implement each screen.",
			changes = CHANGES,
			conclusion = "Habit Garden is running in the preview. Your check-ins stay on this device." },
	},
}

local SUGGESTIONS = {
	{ title = "Add a feature", icon = "plus" },
	{ title = "Fix a bug", icon = "ladybug" },
	{ title = "Polish the UI", icon = "wand.and.stars" },
}

-- A diff line's colour: added green, removed red, context secondary.
local function diffLine(text)
	local sign = text:sub(1, 1)
	return { text = text, color = sign == "+" and "systemGreen" or (sign == "-" and "systemRed" or "secondary") }
end

-- `list` is {path, added, removed, lines}; `lines` are diff lines shown
-- under the file's row.
function Model.changes(list)
	local result, added, removed = {}, 0, 0
	for _, change in ipairs(list) do
		added = added + change.added
		removed = removed + (change.removed or 0)
		local lines = {}
		for _, line in ipairs(change.lines or {}) do table.insert(lines, diffLine(line)) end
		table.insert(result, {
			path = change.path,
			name = change.path:match("[^/]+$"),
			folder = change.path:match("^(.+)/[^/]+$") or "",
			icon = ICONS[change.path:match("%.(%w+)$")] or "doc",
			delta = "+" .. change.added .. ((change.removed or 0) > 0 and (" −" .. change.removed) or ""),
			lines = lines,
		})
	end
	local noun = #result == 1 and "file" or "files"
	local delta = "+" .. added .. (removed > 0 and (" −" .. removed) or "")
	return result, { title = #result .. " " .. noun .. " changed", delta = delta }
end

-- `conversation` ({messages, draft, listening}) replaces the starter
-- conversation, as a showcase does. An agent message may carry `changes`
-- (a change card) and a `conclusion`.
function Model.presentation(conversation, code)
	local source = conversation or Model.DEFAULT
	local messages = {}
	for index, message in ipairs(source.messages or {}) do
		local entry = { id = index, role = message.role, text = message.text, conclusion = message.conclusion }
		if message.changes and #message.changes > 0 then
			entry.changes, entry.summary = Model.changes(message.changes)
		end
		table.insert(messages, entry)
	end
	return {
		agent = { name = "Assistant", model = "openrouter/free", icon = "sparkles" },
		brand = Theme.brand,
		tint = Theme.tint,
		messages = messages,
		draft = source.draft or "",
		listening = source.listening == true,
		suggestions = SUGGESTIONS,
		code = code or Code.presentation({}),
		syntaxRules = Code.rules,
	}
end

return Model
