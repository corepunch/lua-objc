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
}

function Session.new(options)
	options = options or {}
	return setmetatable({
		engineFactory = options.engineFactory,
		messages = {},
		moves = 0,
		score = 0,
		maxScore = 0,
		availableDirections = {},
		roomTitle = nil,
	}, Session)
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
			self.availableDirections = {}
			for _, direction in ipairs(directions) do
				local normalized = DIRECTIONS[tostring(direction):lower()]
				if normalized then self.availableDirections[normalized] = true end
			end
		end
	end
	if type(self.engine.roomName) == "function" then
		local ok, name = pcall(self.engine.roomName, self.engine)
		if ok and type(name) == "string" and name:match("%S") then
			self.roomTitle = name
		end
	end
end

function Session:hasExit(direction)
	local normalized = DIRECTIONS[tostring(direction or ""):lower()]
	return normalized ~= nil and self.availableDirections[normalized] == true
end

function Session:start(game)
	if not game then return false, "Adventure not found." end
	if not self.engineFactory then return false, "No session engine configured." end
	local ok, engine, opening = pcall(function()
		return self.engineFactory(game):start()
	end)
	if not ok then return false, tostring(engine) end
	self.engine, self.currentGame = engine, game
	self.messages = { tostring(opening or "") }
	self.moves, self.score, self.maxScore = 0, 0, 0
	self.availableDirections = {}
	self.roomTitle = nil
	self:refreshEngineState()
	return true
end

function Session:submit(command)
	command = tostring(command or ""):match("^%s*(.-)%s*$")
	if command == "" or not self.engine then return false end
	local ok, response = pcall(function() return self.engine:resume(command) end)
	table.insert(self.messages, "> " .. command)
	table.insert(self.messages, tostring(response or ""))
	local movesBefore = self.moves
	self:refreshEngineState()
	if type(self.engine.progress) ~= "function" then
		self.moves = movesBefore + 1
	end
	return ok, response
end

local function splitRoomHeading(text)
	local heading, body = text:match("^([^\n]+)\n\n(.*)$")
	if not heading or #heading > 48 or not heading:match("%a")
		or heading:match("[.!?,;:]") or not body:match("%S") then
		return nil, text
	end

	for word in heading:gmatch("%S+") do
		local lower = word:lower()
		local article = lower == "a" or lower == "an" or lower == "and"
			or lower == "at" or lower == "by" or lower == "for" or lower == "in"
			or lower == "of" or lower == "on" or lower == "the" or lower == "to"
			or lower == "under" or lower == "with"
		if not article and not word:match("^%u[%w'/-]*$") then
			return nil, text
		end
	end
	return heading, body
end

function Session:presentation()
	local opening = self.messages[1] or ""
	local roomTitle, openingBody = splitRoomHeading(opening)
	local transcript = {}
	if openingBody then table.insert(transcript, openingBody)
	elseif opening ~= "" then table.insert(transcript, opening) end
	for index = 2, #self.messages do
		table.insert(transcript, self.messages[index])
	end
	local scoreText = self.maxScore > 0
		and string.format("Score %d/%d", self.score, self.maxScore)
		or string.format("Score %d", self.score)
	local directions = {}
	for direction in pairs(self.availableDirections) do table.insert(directions, direction) end
	table.sort(directions)
	return {
		gameTitle = self.currentGame and self.currentGame.title or "",
		gameDescription = self.currentGame and self.currentGame.description or "",
		roomTitle = self.roomTitle or roomTitle or (self.currentGame and self.currentGame.title) or "",
		transcript = table.concat(transcript, "\n\n"),
		progress = string.format("%s | Moves %d", scoreText, self.moves),
		availableDirections = directions,
	}
end

return Session
