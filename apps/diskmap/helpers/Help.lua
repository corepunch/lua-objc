local Help = {}

Help.chapters = require("apps.diskmap.knowledge.Help")

-- macOS writes modifier symbols in the order Control, Option, Shift,
-- Command, then the key.
local MODIFIERS = {{"control", "⌃"}, {"option", "⌥"}, {"shift", "⇧"}, {"command", "⌘"}}
local KEYS = {delete = "⌫", ["return"] = "↩", escape = "⎋", tab = "⇥", space = "Space",
	left = "←", right = "→", up = "↑", down = "↓", ["."] = ".", [","] = ","}

-- The symbol string for a menu shortcut: `("r", "command,shift")` → "⇧⌘R".
function Help.shortcut(key, modifiers)
	if not key or key == "" then return nil end
	modifiers = modifiers or "command"
	local text = ""
	for _, pair in ipairs(MODIFIERS) do
		if modifiers:find(pair[1], 1, true) then text = text .. pair[2] end
	end
	return text .. (KEYS[key] or key:upper())
end

local function searchable(topic)
	return table.concat({topic.title, topic.summary, topic.keywords or "", table.concat(topic.steps or {}, " ")}, " "):lower()
end

-- The shortcut topic lists `shortcuts` ({title, key, modifiers}) as its
-- steps, so it always matches the installed menu bar.
local function steps(topic, shortcuts)
	if topic.id ~= "shortcuts" then return topic.steps or {} end
	local lines = {}
	for _, entry in ipairs(shortcuts or {}) do
		local symbol = Help.shortcut(entry.key, entry.modifiers)
		if symbol then table.insert(lines, symbol .. "  " .. entry.title) end
	end
	return lines
end

-- Every chapter and its topics, in help order. `links` maps a topic's
-- `show` page or `command` to the title of its button.
function Help.presentation(shortcuts, links)
	local chapters = {}
	for _, chapter in ipairs(Help.chapters) do
		local topics = {}
		for _, topic in ipairs(chapter.topics) do
			local numbered = {}
			for index, line in ipairs(steps(topic, shortcuts)) do
				table.insert(numbered, topic.id == "shortcuts" and line or (index .. ". " .. line))
			end
			local target = topic.show or topic.command
			table.insert(topics, {id = topic.id, title = topic.title, icon = topic.icon, summary = topic.summary,
				steps = table.concat(numbered, "\n"), note = topic.note,
				target = target, link = target and links and links[target]})
		end
		table.insert(chapters, {id = chapter.id, title = chapter.title, icon = chapter.icon, topics = topics})
	end
	return {chapters = chapters}
end

-- The topics that mention `needle` (lowered), in help order: those of a
-- chapter whose title matches, and any whose text or keywords do.
function Help.search(needle)
	local found = {}
	for _, chapter in ipairs(Help.chapters) do
		local chapterMatches = chapter.title:lower():find(needle, 1, true) ~= nil
		for _, topic in ipairs(chapter.topics) do
			if chapterMatches or searchable(topic):find(needle, 1, true) then
				table.insert(found, {id = topic.id, title = topic.title, icon = topic.icon, summary = topic.summary, chapter = chapter.title})
			end
		end
	end
	return found
end

-- Every topic as a Help-menu search entry: `{id, title, keywords}`.
function Help.searchTopics()
	local topics = {}
	for _, chapter in ipairs(Help.chapters) do
		for _, topic in ipairs(chapter.topics) do
			table.insert(topics, {id = topic.id, title = topic.title,
				keywords = table.concat({chapter.title, topic.summary, topic.keywords or ""}, " ")})
		end
	end
	return topics
end

function Help.topic(id)
	for _, chapter in ipairs(Help.chapters) do
		for _, topic in ipairs(chapter.topics) do if topic.id == id then return topic end end
	end
end

return Help
