-- Type-ahead for the command line. Prior art: iOS Frotz completes words from
-- the story file's dictionary, and inkle's games show only verbs that make
-- sense right now. This model does both: verbs come from a ranked common set
-- plus the verbs the engine reports for visible objects, nouns come from the
-- objects in the room (then ones seen earlier), and directions from exits.
local Suggestions = {}

local LIMIT = 6

-- Ordered by how often players type them, so "l" offers "look" first.
local VERBS = {
	"look", "examine", "open", "take", "inventory", "read", "go", "drop",
	"close", "enter", "turn on", "turn off", "push", "pull", "move", "put",
	"give", "unlock", "lock", "climb", "light", "search", "listen", "smell",
	"wait", "attack", "eat", "drink", "wear", "remove", "throw", "tie",
	"knock", "jump", "exit", "turn", "ask", "tell", "say", "touch",
}
local VERB_RANK = {}
for index, verb in ipairs(VERBS) do VERB_RANK[verb] = index end

local DIRECTIONS = {
	"north", "south", "east", "west", "northeast", "northwest",
	"southeast", "southwest", "up", "down", "in", "out",
}

-- Verbs whose object is usually followed by a second one ("put coin in slot").
local PREPOSITIONS = {
	put = { "in", "on", "under" }, give = { "to" }, unlock = { "with" },
	lock = { "with" }, attack = { "with" }, tie = { "to" }, throw = { "at", "in" },
	open = { "with" }, light = { "with" }, show = { "to" },
}

-- Verbs whose object needs a second one make poor one-tap commands.
local NEEDS_SECOND = { put = true, give = true, tie = true, throw = true, show = true, unlock = true, lock = true }

local function startsWith(text, prefix)
	return prefix == "" or text:sub(1, #prefix) == prefix
end

-- Engine action names are ZIL identifiers such as LOOK-BEHIND.
local function playerVerb(action)
	return (tostring(action):lower():gsub("-", " "))
end

-- "small mailbox" is typed as "mailbox": ZIL parsers match the final noun.
function Suggestions.noun(name)
	local words = {}
	for word in tostring(name or ""):lower():gmatch("[%w']+") do table.insert(words, word) end
	return words[#words]
end

-- Flatten engine room items ({ name, verbs, children }) into nouns the
-- parser understands, keeping nested contents such as a leaflet in a mailbox.
function Suggestions.items(raw)
	local items, seen = {}, {}
	local function visit(list)
		for _, entry in ipairs(type(list) == "table" and list or {}) do
			local name = type(entry) == "table" and entry[1] or entry
			local noun = Suggestions.noun(name)
			if noun and not seen[noun] then
				seen[noun] = true
				local verbs = {}
				for _, action in ipairs(type(entry) == "table" and entry[2] or {}) do
					table.insert(verbs, playerVerb(action))
				end
				table.insert(items, { name = tostring(name), noun = noun, verbs = verbs })
			end
			if type(entry) == "table" then visit(entry[3]) end
		end
	end
	visit(raw)
	return items
end

local function itemSupports(item, verb)
	for _, candidate in ipairs(item.verbs or {}) do
		if candidate == verb then return true end
	end
	return false
end

-- The verb a player most likely wants for an item: the best-ranked common
-- verb the engine lists for it, else "examine".
local function primaryVerb(item)
	local best, bestRank
	for _, verb in ipairs(item.verbs or {}) do
		local rank = VERB_RANK[verb]
		if rank and verb ~= "look" and not NEEDS_SECOND[verb] and (not bestRank or rank < bestRank) then
			best, bestRank = verb, rank
		end
	end
	return best or "examine"
end

local function tokenize(input)
	local words = {}
	for word in input:lower():gmatch("%S+") do table.insert(words, word) end
	local trailing = input:match("%s$") ~= nil
	local current = ""
	if not trailing and #words > 0 then current = table.remove(words) end
	return words, current
end

local function collector()
	local list, seen = {}, {}
	return list, function(title, text, submit)
		if #list >= LIMIT or seen[text] then return end
		seen[text] = true
		table.insert(list, { title = title, text = text, submit = submit == true })
	end
end

-- context = { items = {...}, knownItems = {...}, exits = {...} }
-- Returns up to six { title, text, submit } chips. A chip with submit=true
-- is a whole command; otherwise its text replaces the composer contents.
function Suggestions.forInput(input, context)
	input = tostring(input or "")
	context = context or {}
	local items, exits = context.items or {}, context.exits or {}
	local nouns = {}
	for _, item in ipairs(items) do table.insert(nouns, item) end
	local present = {}
	for _, item in ipairs(items) do present[item.noun] = true end
	for _, item in ipairs(context.knownItems or {}) do
		if not present[item.noun] then table.insert(nouns, item) present[item.noun] = true end
	end

	local list, add = collector()
	local words, current = tokenize(input)
	local head = table.concat(words, " ")
	local prefix = head == "" and "" or head .. " "

	if #words == 0 and current == "" then
		-- An empty composer offers the moves that make sense right here.
		for index = 1, math.min(2, #exits) do add(exits[index], exits[index], true) end
		for _, item in ipairs(items) do
			local command = primaryVerb(item) .. " " .. item.noun
			add(command, command, true)
			if #list >= LIMIT - 2 then break end
		end
		add("look", "look", true)
		add("inventory", "inventory", true)
		return list
	end

	if #words == 0 then
		-- First word: the likeliest verbs, then exits and objects ("t" offers
		-- "take" and also "examine table"), then the rarer verbs.
		local verbs = {}
		for _, verb in ipairs(VERBS) do
			if startsWith(verb, current) then table.insert(verbs, verb) end
		end
		for index = 1, math.min(3, #verbs) do add(verbs[index], verbs[index] .. " ") end
		for _, direction in ipairs(exits) do
			if startsWith(direction, current) then add(direction, direction, true) end
		end
		for _, item in ipairs(nouns) do
			if startsWith(item.noun, current) then
				local command = primaryVerb(item) .. " " .. item.noun
				add(command, command .. " ")
			end
		end
		for index = 4, #verbs do add(verbs[index], verbs[index] .. " ") end
		return list
	end

	local verb = words[1]
	if #words >= 2 and VERB_RANK[words[1] .. " " .. words[2]] then verb = words[1] .. " " .. words[2] end
	if verb == "go" or verb == "walk" or verb == "run" then
		for _, direction in ipairs(exits) do
			if startsWith(direction, current) then add(direction, prefix .. direction, true) end
		end
		for _, direction in ipairs(DIRECTIONS) do
			if startsWith(direction, current) then add(direction, prefix .. direction, true) end
		end
		return list
	end

	-- "turn o" completes the particle of a two-word verb.
	if #words == 1 then
		for _, candidate in ipairs(VERBS) do
			if candidate:sub(1, #head + 1) == head .. " " then
				local particle = candidate:sub(#head + 2)
				if startsWith(particle, current) then add(particle, prefix .. particle .. " ") end
			end
		end
	end

	-- After "verb noun " offer the joining word, after a joining word a noun.
	local last = words[#words]
	local joins = PREPOSITIONS[verb]
	local lastIsNoun = present[last] and last ~= verb
	if joins and lastIsNoun then
		for _, join in ipairs(joins) do
			if startsWith(join, current) then add(join, prefix .. join .. " ") end
		end
	end
	-- When the story says which objects answer this verb, offer only those;
	-- otherwise ("examine", "take" of scenery) every object is fair game.
	local anyFits = false
	for _, item in ipairs(nouns) do
		if itemSupports(item, verb) then anyFits = true break end
	end
	for _, item in ipairs(nouns) do
		if (not anyFits or itemSupports(item, verb)) and startsWith(item.noun, current) and item.noun ~= last then
			add(item.noun, prefix .. item.noun .. " ")
		end
	end
	return list
end

Suggestions.VERBS, Suggestions.DIRECTIONS = VERBS, DIRECTIONS

return Suggestions
