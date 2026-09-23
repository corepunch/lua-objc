local Adventures = {}
Adventures.__index = Adventures

function Adventures.new(options)
	options = options or {}
	local games = options.games or require("apps.adventure-arena.catalog.Adventures")
	local gamesById = {}
	for _, game in ipairs(games) do gamesById[game.id] = game end
	return setmetatable({ games = games, gamesById = gamesById }, Adventures)
end

function Adventures:list()
	local games = {}
	for index, game in ipairs(self.games) do games[index] = game end
	return games
end

function Adventures:find(id)
	return self.gamesById[id]
end

function Adventures:featured()
	local games = {}
	for index = 1, math.min(3, #self.games) do games[index] = self.games[index] end
	return games
end

return Adventures
