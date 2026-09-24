local Session = {}
Session.__index = Session

function Session.new(options)
	options = options or {}
	return setmetatable({ engineFactory = options.engineFactory, messages = {}, moves = 0, score = 0 }, Session)
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
	self.moves, self.score = 0, 0
	return true
end

function Session:submit(command)
	command = tostring(command or ""):match("^%s*(.-)%s*$")
	if command == "" or not self.engine then return false end
	local ok, response = pcall(function() return self.engine:resume(command) end)
	table.insert(self.messages, "> " .. command)
	table.insert(self.messages, tostring(response or ""))
	self.moves = self.moves + 1
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
	return {
		roomTitle = roomTitle or (self.currentGame and self.currentGame.title) or "",
		transcript = table.concat(transcript, "\n\n"),
		progress = string.format("Score %d | Moves %d", self.score, self.moves),
	}
end

return Session
