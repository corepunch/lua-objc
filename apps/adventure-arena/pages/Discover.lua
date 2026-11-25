local Adventures = require("apps.adventure-arena.models.Adventures")
local SavedGames = require("apps.adventure-arena.models.SavedGames")

return {
	discover = {
		view = "pages/Adventures",
		data = function(self)
			local games, inProgress = Adventures:all(), SavedGames:inProgress()
			local shelves, topRated = Adventures:genreShelves(), Adventures:topRated()
			for _, shelf in ipairs(Adventures:shelves()) do table.insert(shelves, shelf) end
			local handlers = {}
			for _, entry in ipairs(inProgress) do
				local id = entry.game.id
				handlers["continueStory_" .. id] = function() return self:flow("Opening"):story(id) end
			end
			for _, game in ipairs(games) do
				handlers[game.id] = function() self:flow("Opening"):game(game.id) end
			end
			for index, shelf in ipairs(shelves) do
				handlers["shelf_" .. index] = function() self:flow("Opening"):collection(shelf.title) end
			end
			for index, entry in ipairs(topRated) do
				handlers["chart_" .. index] = function() self:flow("Opening"):game(entry.game.id) end
			end
			return { games = games, inProgress = inProgress, shelves = shelves, topRated = topRated,
				handlers = handlers }
		end,
		openCreate = function(self) self.app.openCatalogPage("create") end,
		openSearch = function(self) self.app.openCatalogPage("search") end,
		openSettings = function(self) self.app.openCatalogPage("settings") end,
		queries = { openCreate = true, openSearch = true, openSettings = true },
	},
}
