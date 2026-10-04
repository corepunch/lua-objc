local Adventures = require("apps.adventure-arena.models.Adventures")

-- A shelf or genre in full ("See All"), pushed like a detail page.
return {
	collection = {
		view = "pages/Collection",
		before = function(self, state)
			self.title, self.origin = state.title, state.origin
		end,
		data = function(self)
			local games = Adventures:collection(self.title)
			local handlers = {}
			for _, game in ipairs(games) do
				handlers[game.id] = function() self:flow("Opening"):game(game.id, self.origin) end
			end
			return { title = self.title, games = games, handlers = handlers }
		end,
	},
}
