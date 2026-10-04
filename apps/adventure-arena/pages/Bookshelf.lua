local SavedGames = require("apps.adventure-arena.models.SavedGames")

-- The Library tab: every story in progress with Start Over and Remove, and
-- the tab bar accessory that resumes the latest one.
return {
	bookshelf = {
		view = "pages/Bookshelf",
		data = function(self)
			local origin = self.params.origin
			local entries = SavedGames:inProgress()
			local handlers = {}
			for index, entry in ipairs(entries) do
				local id = entry.game.id
				handlers["continue_" .. index] = function() self:flow("Opening"):story(id, origin) end
				handlers["restart_" .. index] = function() self:flow("Opening"):story(id, origin, true) end
				handlers["remove_" .. index] = function() self:remove(id) end
			end
			return { entries = entries, handlers = handlers }
		end,
		browseDiscover = function(self) self.app.selectTab("library") end,
		remove = function(self, id) return SavedGames:remove(id) end,
	},
	nowReading = {
		view = "sections/NowReading",
		data = function(self)
			local latest = SavedGames:latest()
			local entry = latest and latest:progress()
			self.resumable = entry ~= nil
			return { game = entry and entry.game, place = entry and entry.place or "" }
		end,
		resume = function(self) self.app.resume() end,
		-- The accessory belongs to the tab bar: an open book hides it, and so
		-- does having nothing to resume.
		rendered = function(self) self.app.showAccessory(self.resumable) end,
		queries = { resume = true },
	},
}
