local Adventures = require("apps.adventure-arena.models.Adventures")
local SavedGames = require("apps.adventure-arena.models.SavedGames")

-- Discover and its "Continue Reading" shelf. Row actions are named by the
-- data (`handlers`): a button per game, shelf and genre.
return {
	discover = {
		view = "pages/Adventures",
		data = function(self)
			local origin = self.params.origin
			local games, featured = Adventures:all(), Adventures:featured()
			local shelves, topRated, genres = Adventures:shelves(), Adventures:topRated(), Adventures:genres()
			local handlers = {}
			for index, game in ipairs(featured) do
				handlers["featured_" .. index] = function() self:flow("Opening"):game(game.id, origin) end
			end
			for _, game in ipairs(games) do
				handlers[game.id] = function() self:flow("Opening"):game(game.id, origin) end
			end
			for index, shelf in ipairs(shelves) do
				handlers["shelf_" .. index] = function() self:flow("Opening"):collection(shelf.title, origin) end
			end
			for index, entry in ipairs(topRated) do
				handlers["chart_" .. index] = function() self:flow("Opening"):game(entry.game.id, origin) end
			end
			for index, genre in ipairs(genres) do
				handlers["genre_" .. index] = function() self:flow("Opening"):collection(genre.title, origin) end
			end
			return { games = games, featured = featured, shelves = shelves, topRated = topRated, genres = genres,
				handlers = handlers }
		end,
		openCreate = function(self) self.app.selectTab("create") end,
		-- The tab bar reports which tab the reader chose.
		tabChanged = function(self, _, index) self.app.tabChanged(tonumber(index) or 0) end,
		queries = { openCreate = true, tabChanged = true },
	},
	continueShelf = {
		view = "sections/ContinueShelf",
		data = function(self)
			local entries = SavedGames:inProgress()
			local handlers = {}
			for index, entry in ipairs(entries) do
				handlers["continue_" .. index] = function() self:flow("Opening"):story(entry.game.id, self.params.origin) end
			end
			return { continueGames = entries, handlers = handlers }
		end,
	},
}
