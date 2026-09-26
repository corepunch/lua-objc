local Suggestions = require("apps.adventure-arena.models.Suggestions")

local Session = {}
Session.__index = Session

local DIRECTIONS = {
	n = "north", north = "north",
	ne = "northeast", northeast = "northeast",
	e = "east", east = "east",
	se = "southeast", southeast = "southeast",
	s = "south", south = "south",
	sw = "southwest", southwest = "southwest",
	w = "west", west = "west",
	nw = "northwest", northwest = "northwest",
	u = "up", up = "up", d = "down", down = "down",
	["in"] = "in", out = "out",
}

-- Re-rendering a transcript costs time proportional to its length, so the
-- reader keeps the most recent entries; the story itself is unaffected.
local TRANSCRIPT = { limit = 120 }

local ROMAN = {
	{ 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" },
	{ 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" },
}

function Session.roman(number)
	local parts = {}
	for _, pair in ipairs(ROMAN) do
		while number >= pair[1] do
			table.insert(parts, pair[2])
			number = number - pair[1]
		end
	end
	return table.concat(parts)
end

function Session.new(options)
	options = options or {}
	local self = setmetatable({ engineFactory = options.engineFactory }, Session)
	self:reset()
	return self
end

function Session:reset()
	self.entries, self.history = {}, {}
	self.moves, self.score, self.maxScore, self.chapters = 0, 0, 0, 0
	self.availableDirections, self.exitList = {}, {}
	self.items, self.knownItems, self.knownByNoun = {}, {}, {}
	self.roomTitle, self.scene, self.openEntry = nil, nil, nil
end

function Session:refreshEngineState()
	if type(self.engine.progress) == "function" then
		local ok, progress = pcall(self.engine.progress, self.engine)
		if ok and type(progress) == "table" then
			self.score = tonumber(progress.score) or 0
			self.moves = tonumber(progress.moves) or 0
			self.maxScore = tonumber(progress.maxScore) or 0
		end
	end
	if type(self.engine.exits) == "function" then
		local ok, directions = pcall(self.engine.exits, self.engine)
		if ok and type(directions) == "table" then
			self.availableDirections, self.exitList = {}, {}
			for _, direction in ipairs(directions) do
				local normalized = DIRECTIONS[tostring(direction):lower()]
				if normalized and not self.availableDirections[normalized] then
					self.availableDirections[normalized] = true
					table.insert(self.exitList, normalized)
				end
			end
			-- The engine walks exits in hash order; players expect a compass.
			local order = {}
			for index, direction in ipairs(Suggestions.DIRECTIONS) do order[direction] = index end
			table.sort(self.exitList, function(a, b) return order[a] < order[b] end)
		end
	end
	if type(self.engine.roomName) == "function" then
		local ok, name = pcall(self.engine.roomName, self.engine)
		if ok and type(name) == "string" and name:match("%S") then
			self.roomTitle = name
		end
	end
	if type(self.engine.items) == "function" then
		local ok, raw = pcall(self.engine.items, self.engine)
		if ok and type(raw) == "table" then
			self.items = Suggestions.items(raw)
			-- Objects stay suggestible after they leave the room: most of
			-- them left in the player's hands.
			for _, item in ipairs(self.items) do
				if not self.knownByNoun[item.noun] then
					self.knownByNoun[item.noun] = item
					table.insert(self.knownItems, item)
				end
			end
		end
	end
end

function Session:hasExit(direction)
	local normalized = DIRECTIONS[tostring(direction or ""):lower()]
	return normalized ~= nil and self.availableDirections[normalized] == true
end

-- ── Transcript structure ────────────────────────────────────────────────
-- The engine prints plain text. Books give the reader structure, so the
-- transcript is parsed into a title-page banner, scenes (a new room opens a
-- chapter with an illuminated initial), the player's own commands, and
-- narration.

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function paragraphsOf(text)
	local paragraphs = {}
	text = tostring(text or ""):gsub("\r\n", "\n")
	for block in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
		local paragraph = trim(block)
		if paragraph ~= "" then table.insert(paragraphs, paragraph) end
	end
	return paragraphs
end

local function isBanner(paragraph)
	return paragraph:find("Copyright", 1, true) ~= nil
		or paragraph:match("Release %d+ / Serial") ~= nil
end

local SMALL_WORDS = {
	a = true, an = true, ["and"] = true, at = true, by = true, ["for"] = true, ["in"] = true,
	of = true, on = true, the = true, to = true, under = true, with = true,
}

-- Without an engine room name, a heading is a short title-cased line.
local function looksLikeHeading(line)
	if #line > 48 or not line:match("%a") or line:match("[.!?,;:]") then return false end
	for word in line:gmatch("%S+") do
		if not SMALL_WORDS[word:lower()] and not word:match("^%u[%w'/-]*$") then return false end
	end
	return true
end

local function splitFirstLine(paragraph)
	local first, rest = paragraph:match("^([^\n]+)\n(.*)$")
	if not first then return paragraph, nil end
	rest = trim(rest)
	return trim(first), rest ~= "" and rest or nil
end

function Session:beginScene(title)
	self.chapters = self.chapters + 1
	local scene = {
		kind = "scene", chapter = self.chapters, chapterLabel = "Chapter " .. Session.roman(self.chapters),
		title = title, paragraphs = {},
	}
	table.insert(self.entries, scene)
	self.scene, self.openEntry = scene, scene
	return scene
end

function Session:appendParagraph(paragraph)
	if not self.openEntry then
		self.openEntry = { kind = "narration", paragraphs = {} }
		table.insert(self.entries, self.openEntry)
	end
	table.insert(self.openEntry.paragraphs, paragraph)
end

function Session:appendOutput(text, openingTitle)
	local paragraphs = paragraphsOf(text)
	local room = self.roomTitle
	local headingFound = false
	for _, paragraph in ipairs(paragraphs) do
		local first = splitFirstLine(paragraph)
		if (room and first == room) or (not room and looksLikeHeading(first) and first ~= paragraph) then
			headingFound = true
		end
	end
	-- A move without a printed heading still enters a new room: the scene
	-- opens at the first paragraph that is not the title page.
	-- The opening always starts Chapter I, even when the engine names no room.
	local pendingRoom = not headingFound and (room or openingTitle)
		and (not self.scene or self.scene.title ~= (room or openingTitle)) and (room or openingTitle) or nil

	for _, paragraph in ipairs(paragraphs) do
		if isBanner(paragraph) then
			local title, rest = splitFirstLine(paragraph)
			local lines = {}
			for line in (rest or ""):gmatch("[^\n]+") do table.insert(lines, trim(line)) end
			table.insert(self.entries, { kind = "banner", title = title, lines = lines })
			self.openEntry = nil
		else
			local first, rest = splitFirstLine(paragraph)
			local heading = (room and first == room) or (not room and rest and looksLikeHeading(first))
			if heading then
				if not self.scene or self.scene.title ~= first then
					self:beginScene(first)
				end
				if rest then self:appendParagraph(rest) end
			else
				if pendingRoom then
					self:beginScene(pendingRoom)
					pendingRoom = nil
				end
				self:appendParagraph(paragraph)
			end
		end
	end
end

function Session:start(game)
	if not game then return false, "Adventure not found." end
	if not self.engineFactory then return false, "No session engine configured." end
	local ok, engine, opening = pcall(function()
		return self.engineFactory(game):start()
	end)
	if not ok then return false, tostring(engine) end
	self:reset()
	self.engine, self.currentGame = engine, game
	self:refreshEngineState()
	self:appendOutput(opening, game.title)
	return true
end

function Session:submit(command)
	command = tostring(command or ""):match("^%s*(.-)%s*$")
	if command == "" or not self.engine then return false end
	local ok, response = pcall(function() return self.engine:resume(command) end)
	table.insert(self.history, command)
	table.insert(self.entries, { kind = "command", text = command })
	self.openEntry = nil
	local movesBefore = self.moves
	self:refreshEngineState()
	if type(self.engine.progress) ~= "function" then
		self.moves = movesBefore + 1
	end
	self:appendOutput(response)
	return ok, response
end

function Session:suggestions(input)
	return Suggestions.forInput(input, {
		items = self.items, knownItems = self.knownItems, exits = self.exitList,
	})
end

-- The first letter of a scene is set as an illuminated initial; the rest of
-- that paragraph (the "lead") runs beside it, like an old storybook.
local function illuminate(scene)
	local first = scene.paragraphs[1] or ""
	local initial, lead = first:match("^(%a)(.*)$")
	local rest = {}
	for index = initial and 2 or 1, #scene.paragraphs do table.insert(rest, scene.paragraphs[index]) end
	return {
		kind = "scene", chapter = scene.chapter, chapterLabel = scene.chapterLabel, title = scene.title,
		initial = initial and initial:upper(), lead = initial and lead or nil, paragraphs = rest,
	}
end

function Session:transcript(limit)
	limit = limit or TRANSCRIPT.limit
	local entries = {}
	for index = math.max(1, #self.entries - limit + 1), #self.entries do
		local entry = self.entries[index]
		if entry.kind == "scene" then
			table.insert(entries, illuminate(entry))
		else
			table.insert(entries, entry)
		end
	end
	return entries, math.max(0, #self.entries - limit)
end

function Session:presentation()
	local game = self.currentGame or {}
	local scoreText = self.maxScore > 0
		and string.format("Score %d/%d", self.score, self.maxScore)
		or string.format("Score %d", self.score)
	local directions = {}
	for direction in pairs(self.availableDirections) do table.insert(directions, direction) end
	table.sort(directions)
	local entries, earlier = self:transcript()
	return {
		gameTitle = game.title or "",
		gameDescription = game.description or "",
		gameAuthor = game.author or "",
		gameYear = game.year and tostring(game.year) or "",
		cover = game.cover,
		tint = game.tint or "accent",
		initialFont = game.initialFont,
		roomTitle = self.roomTitle or (self.scene and self.scene.title) or game.title or "",
		entries = entries,
		earlierEntries = earlier,
		progress = string.format("%s | Moves %d", scoreText, self.moves),
		availableDirections = directions,
	}
end

return Session
