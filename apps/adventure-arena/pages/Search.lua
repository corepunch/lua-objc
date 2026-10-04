local Adventures = require("apps.adventure-arena.models.Adventures")

-- Search results: each keystroke asks again, and the retained template
-- swaps only what the new results change.
return {
	search = {
		view = "sections/SearchResults",
		init = function(self) self.query = "" end,
		data = function(self)
			local origin = self.params.origin
			local results, genres = Adventures:search(self.query), Adventures:genres()
			local handlers = {}
			for index, game in ipairs(results) do
				handlers["result_" .. index] = function() self:flow("Opening"):game(game.id, origin) end
			end
			for index, genre in ipairs(genres) do
				handlers["genre_" .. index] = function() self:flow("Opening"):collection(genre.title, origin) end
			end
			return { query = self.query, results = results, genres = genres, handlers = handlers }
		end,
		search = function(self, text) self.query = tostring(text or ""):match("^%s*(.-)%s*$") end,
	},
}
