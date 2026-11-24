local Adventures = require("apps.adventure-arena.models.Adventures")

-- Discover supplies a button per game and shelf.
return {
	discover = {
		view = "pages/Adventures",
		data = function(self)
			local games, featured = Adventures:all(), Adventures:featured()
			local shelves, topRated = Adventures:genreShelves(), Adventures:topRated()
			for _, shelf in ipairs(Adventures:shelves()) do table.insert(shelves, shelf) end
			local handlers = {}
			for index, game in ipairs(featured) do
				handlers["featured_" .. index] = function() self:flow("Opening"):game(game.id) end
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
			return { games = games, featured = featured, shelves = shelves, topRated = topRated,
				handlers = handlers }
		end,
		openCreate = function(self) self.app.openCatalogPage("create") end,
		openSearch = function(self) self.app.openCatalogPage("search") end,
		openSettings = function(self) self.app.openCatalogPage("settings") end,
		queries = { openCreate = true, openSearch = true, openSettings = true },
	},
}
