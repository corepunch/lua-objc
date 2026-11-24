local SavedGames = require("apps.adventure-arena.models.SavedGames")

-- The Settings page: the reading options (a coordinating controller owns
-- them, they are shared with the in-book sheet) and the guide.
return {
	settings = {
		view = "pages/Settings",
		data = function(self)
			local entries = SavedGames:inProgress()
			local handlers = {}
			for index, entry in ipairs(entries) do
				local id = entry.game.id
				handlers["continue_" .. index] = function() return self:flow("Opening"):story(id) end
				handlers["restart_" .. index] = function() return self:flow("Opening"):story(id, true) end
				handlers["remove_" .. index] = function() return self:remove(id) end
			end
			return { entries = entries, handlers = handlers }
		end,
		remove = function(self, id) return SavedGames:remove(id) end,
		howToPlay = function(self) self.app.openGuide() end,
		queries = { howToPlay = true },
		rendered = function(self, refs) self.app.mountReadingOptions(refs.readingOptions) end,
	},
}
