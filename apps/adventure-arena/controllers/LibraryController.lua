local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "library model is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		focus = options.focus or function() end,
		openSession = assert(options.openSession, "session callback is required"),
		query = "",
	}, Controller)
end

-- `origin` names the navigation stack a tap came from ("library" or
-- "search"), so detail and session pages open in the tab the player is using.
function Controller:presentation()
	local games, featured = self.model:list(), self.model:featured()[1]
	local shelves, topRated, genres = self.model:shelves(), self.model:topRated(), self.model:genres()
	local actions = {
		search = function(text) self:search(text) end,
	}
	if featured then actions.featured = function() self:showGame(featured.id, "library") end end
	for _, game in ipairs(games) do
		actions[game.id] = function() self:showGame(game.id, "library") end
	end
	for index, shelf in ipairs(shelves) do
		actions["shelf_" .. index] = function() self:showCollection(shelf.title, "library") end
	end
	for index, entry in ipairs(topRated) do
		actions["chart_" .. index] = function() self:showGame(entry.game.id, "library") end
	end
	for index, genre in ipairs(genres) do
		actions["genre_" .. index] = function() self:showCollection(genre.title, "library") end
	end
	return {
		games = games, featured = featured, shelves = shelves, topRated = topRated, genres = genres,
		actions = actions,
	}
end

function Controller:showGame(id, origin)
	local game = self.model:find(id)
	if not game then return false end
	self.focus(origin)
	local related = self.model:related(id)
	local actions = {
		play = function() self.openSession(id) end,
		back = self.back,
	}
	for index, other in ipairs(related) do
		actions["related_" .. index] = function() self:showGame(other.id, origin) end
	end
	self.push("Detail", { game = game, related = related, actions = actions })
	return true
end

function Controller:showCollection(title, origin)
	local games = self.model:collection(title)
	if #games == 0 then return false end
	self.focus(origin)
	local actions = {}
	for _, game in ipairs(games) do
		actions[game.id] = function() self:showGame(game.id, origin) end
	end
	self.push("Collection", { title = title, games = games, actions = actions })
	return true
end

-- Search results are a retained template: each keystroke re-describes the
-- result list and the template swaps only when the description changes.
function Controller:attachSearch(template)
	self.searchResults = template
	return self:search(self.query)
end

function Controller:search(query)
	self.query = tostring(query or ""):match("^%s*(.-)%s*$")
	if not self.searchResults then return nil end
	local results, genres = self.model:search(self.query), self.model:genres()
	local actions = {}
	for index, game in ipairs(results) do
		actions["result_" .. index] = function() self:showGame(game.id, "search") end
	end
	for index, genre in ipairs(genres) do
		actions["genre_" .. index] = function() self:showCollection(genre.title, "search") end
	end
	local _, refs = self.searchResults:update({
		query = self.query, results = results, genres = genres, actions = actions,
	})
	return results, refs
end

return Controller
