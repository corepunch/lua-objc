local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "library model is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		openSession = assert(options.openSession, "session callback is required"),
	}, Controller)
end

function Controller:presentation()
	local games, featured = self.model:list(), self.model:featured()[1]
	local actions = {}
	if featured then actions.featured = function() self:showGame(featured.id) end end
	for _, game in ipairs(games) do
		actions[game.id] = function() self:showGame(game.id) end
	end
	return { games = games, featured = featured, actions = actions }
end

function Controller:showGame(id)
	local game = self.model:find(id)
	if not game then return false end
	self.push("Detail", { game = game, actions = {
		play = function() self.openSession(id) end,
		back = self.back,
	} }, game.title)
	return true
end

return Controller
