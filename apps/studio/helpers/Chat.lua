local Model = {}
local Code = require("apps.studio.helpers.Code")
local Theme = require("apps.studio.helpers.Theme")

-- Templates get a code symbol and Lua modules a document symbol. Each row
-- shows the file name, with its folder beneath it rather than the full path.
local ICONS = { etlua = "chevron.left.forwardslash.chevron.right", lua = "doc.text" }

local SUGGESTIONS = {
	{ title = "Add a feature", icon = "plus", action = "suggestFeature", prompt = "Add a useful feature to this app." },
	{ title = "Fix a bug", icon = "ladybug", action = "suggestFix", prompt = "Inspect this app and fix a bug." },
	{ title = "Polish the UI", icon = "wand.and.stars", action = "suggestPolish", prompt = "Polish this app using native controls and accessible layout." },
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
	local source = conversation or { messages = {} }
	local messages = {}
	for index, message in ipairs(source.messages or {}) do
		local entry = { id = index, role = message.role, text = message.text, conclusion = message.conclusion }
		if message.changes and #message.changes > 0 then
			entry.changes, entry.summary = Model.changes(message.changes)
		end
		table.insert(messages, entry)
	end
	return {
		agent = { name = "Assistant", model = source.modelId or "openrouter/free", icon = "sparkles" },
		brand = Theme.brand,
		tint = Theme.tint,
		messages = messages,
		draft = source.draft or "",
		listening = source.listening == true,
		busy = source.busy == true,
		attachments = source.attachments or {},
		projectTitle = source.projectTitle or "Project",
		suggestions = SUGGESTIONS,
		code = code or Code.presentation({}),
		syntaxRules = Code.rules,
	}
end

Model.suggestions = SUGGESTIONS
return Model
