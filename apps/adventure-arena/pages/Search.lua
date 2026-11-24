local Adventures = require("apps.adventure-arena.models.Adventures")

-- Search results: each keystroke asks again, and the retained template
-- swaps only what the new results change.
return {
	search = {
		view = "sections/SearchResults",
		init = function(self) self.query = "" end,
		data = function(self)
			local results = Adventures:search(self.query)
			local handlers = {}
			for index, game in ipairs(results) do
				handlers["result_" .. index] = function() self:flow("Opening"):game(game.id) end
			end
			return { query = self.query, results = results, handlers = handlers }
		end,
		search = function(self, text) self.query = tostring(text or ""):match("^%s*(.-)%s*$") end,
	},
}
