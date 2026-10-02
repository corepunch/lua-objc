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

-- Chapters and topics matching `query`, in help order. `links` maps a
-- topic's `show` page or `command` to the title of its button.
function Help.presentation(query, shortcuts, links)
	local needle = (query or ""):lower()
	local chapters, count = {}, 0
	for _, chapter in ipairs(Help.chapters) do
		local chapterMatches = needle == "" or chapter.title:lower():find(needle, 1, true) ~= nil
		local topics = {}
		for _, topic in ipairs(chapter.topics) do
			local lines = steps(topic, shortcuts)
			if chapterMatches or searchable(topic):find(needle, 1, true) or table.concat(lines, " "):lower():find(needle, 1, true) then
				local numbered = {}
				for index, line in ipairs(lines) do
					table.insert(numbered, topic.id == "shortcuts" and line or (index .. ". " .. line))
				end
				local target = topic.show or topic.command
				table.insert(topics, {id = topic.id, title = topic.title, icon = topic.icon, summary = topic.summary,
					steps = table.concat(numbered, "\n"), note = topic.note,
					target = target, link = target and links and links[target]})
			end
		end
		if #topics > 0 then
			count = count + #topics
			table.insert(chapters, {id = chapter.id, title = chapter.title, icon = chapter.icon, topics = topics})
		end
	end
	return {chapters = chapters, count = count, empty = count == 0}
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

-- The page a TopicsController presents. `context.shortcuts()` lists the
-- menu bar's shortcuts, `context.links` titles the topics' buttons and
-- `context.command(name)` runs a menu command.
function Help.page(context)
	return {id = "help", topic = "HelpTopic", noun = "help topic",
		summary = "How to find what uses your storage and free up space safely. To search help from anywhere, use the Help menu.",
		present = function(query) return Help.presentation(query, context.shortcuts(), context.links) end,
		follow = function(topic)
			local target = topic.target
			return topic.link and function()
				if context.pages[target] then context.show(target) else context.command(target) end
			end
		end}
end

return Help
