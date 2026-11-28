local Adventures = require("apps.adventure-arena.models.Adventures")
local SavedGames = require("apps.adventure-arena.models.SavedGames")
local Routes = require("data.routes")
local Plurals = require("apps.adventure-arena.helpers.Plurals")

-- A story's product page, pushed on the stack the tap came from: the request
-- names the story (`state.id`).
return {
	detail = {
		view = "pages/Detail",
		before = function(self, state)
			self.game = Adventures:find(state.id) or Routes.fail("no story " .. tostring(state.id))
		end,
		data = function(self)
			local related = Adventures:related(self.game.id)
			local record = SavedGames:find(self.game.id)
			local handlers = {}
			for index, other in ipairs(related) do
				handlers["related_" .. index] = function() self:flow("Opening"):game(other.id) end
			end
			return { game = self.game, ratingsText = Plurals.format(self.app.resources(), "ratingsCount", self.game.reviewCount or 0), related = related, saved = record and record:progress() or nil, handlers = handlers }
		end,
		play = function(self) self.app.openSession(self.game.id) end,
		restart = function(self) self.app.openSession(self.game.id, true) end,
		back = function(self) self.app.back() end,
		queries = { play = true, restart = true, back = true },
	},
}
