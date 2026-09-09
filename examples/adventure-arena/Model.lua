local Model = {}

Model.games = require("examples.adventure-arena.Catalog")

local gameIndex = {}
for _, game in ipairs(Model.games) do gameIndex[game.id] = game end

function Model.game(id) return gameIndex[id] end
function Model.featured() return { Model.games[1], Model.games[2], Model.games[3] } end
function Model.ratingLabel(game) return string.format("%.1f (%d)", game.rating, game.reviewCount) end

Model.__index = Model

function Model.new(engineFactory)
	return setmetatable({ messages = {}, engineFactory = engineFactory
		or require("examples.adventure-arena.ZIL").new }, Model)
end

function Model:startSession(game, ns)
	local ok, engine, opening = pcall(function()
		return self.engineFactory(game, ns):start()
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
