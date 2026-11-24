local Adventures = require("apps.adventure-arena.models.Adventures")

-- The full collection opened by a shelf heading.
return {
	collection = {
		view = "pages/Collection",
		before = function(self, state)
			self.title = state.title
		end,
		data = function(self)
			local games = Adventures:collection(self.title)
			local handlers = {}
			for _, game in ipairs(games) do
				handlers[game.id] = function() self:flow("Opening"):game(game.id) end
			end
			return { title = self.title, games = games, handlers = handlers }
		end,
	},
}
