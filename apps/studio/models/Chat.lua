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

-- A chip puts its prompt in the composer; the person finishes the sentence.
local SUGGESTIONS = {
	{ id = "feature", title = "Add a feature", icon = "plus", prompt = "Add a feature: " },
	{ id = "bug", title = "Fix a bug", icon = "ladybug", prompt = "Fix this bug: " },
	{ id = "polish", title = "Polish the UI", icon = "wand.and.stars", prompt = "Polish the UI: " },
}
Model.suggestions = SUGGESTIONS

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

-- What a project's conversation opens with before anyone has spoken.
function Model.welcome(projectName)
	return { role = "agent", text = "Describe what " .. (projectName or "your app")
		.. " should do, or what to change. I read the project, edit its files and the preview reloads." }
end

-- `conversation` ({messages, draft, listening, busy, agent}) replaces the
-- starter conversation: the project's transcript, or a showcase. A
-- message's role is "user", "agent" or "error"; an agent message may
-- carry `changes` (a change card) and a `conclusion`. `agent` names the
-- provider and model answering ({name, model, icon}).
function Model.presentation(conversation, code)
	local source = conversation or Model.DEFAULT
	local messages = {}
	local transcript = source.messages or {}
	-- A project with nothing said yet opens on a welcome; a showcase's
	-- empty conversation is shown as it is.
	if #transcript == 0 and source.project then transcript = { Model.welcome(source.project) } end
	for index, message in ipairs(transcript) do
		local entry = { id = index, role = message.role, text = message.text or "", conclusion = message.conclusion }
		if message.changes and #message.changes > 0 then
			entry.changes, entry.summary = Model.changes(message.changes)
		end
		table.insert(messages, entry)
	end
	local agent = source.agent or { name = "Assistant", model = "No provider", icon = "sparkles" }
	return {
		agent = { name = agent.name, model = agent.model, icon = agent.icon or "sparkles" },
		brand = Theme.brand,
		tint = Theme.tint,
		messages = messages,
		draft = source.draft or "",
		listening = source.listening == true,
		busy = source.busy == true,
		suggestions = SUGGESTIONS,
		code = code or Code.presentation({}),
		syntaxRules = Code.rules,
	}
end

return Model
