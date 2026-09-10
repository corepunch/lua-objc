local Model = {}
Model.__index = Model

function Model.new(options)
	options = options or {}
	local games = options.games or require("examples.adventure-arena.Catalog")
	local gameIndex = {}
	for _, game in ipairs(games) do gameIndex[game.id] = game end
	return setmetatable({
		games = games, gameIndex = gameIndex, messages = {},
		engineFactory = options.engineFactory,
	}, Model)
end

function Model:listGames()
	local games = {}
	for index, game in ipairs(self.games) do games[index] = game end
	return games
end

function Model:game(id)
	return self.gameIndex[id]
end

function Model:featured()
	local games = {}
	for index = 1, math.min(3, #self.games) do games[index] = self.games[index] end
	return games
end

function Model:startSession(id)
	local game = self:game(id)
	if not game then return false, "Adventure not found." end
	if not self.engineFactory then return false, "No session engine configured." end
	local ok, engine, opening = pcall(function()
		return self.engineFactory(game):start()
	end)
	if not ok then return false, tostring(engine) end
	self.engine, self.currentGame = engine, game
	self.messages = { tostring(opening or "") }
	return true
end

function Model:submit(command)
	command = tostring(command or ""):match("^%s*(.-)%s*$")
	if command == "" or not self.engine then return false end
	local ok, response = pcall(function() return self.engine:resume(command) end)
	self.messages[#self.messages + 1] = "> " .. command
	self.messages[#self.messages + 1] = tostring(response or "")
	return ok, response
end

function Model:transcript()
	return table.concat(self.messages, "\n\n")
end

return Model
