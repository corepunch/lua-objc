-- The pages: one route for every list (its <Page list="…">) and the account.
local Routes = require("data.routes")
local Notes = require("demo.cloud-notes.models.Notes")

return {
	list = {
		view = "pages/List",
		queries = {setDraft = true, selectNote = true},
		load = function(self)
			return Notes:query({list = self.params.list}, {order = "createdAt desc", limit = 100})
		end,
		data = function(self, state)
			local items = {}
			for _, note in ipairs(Notes:of(self.params.list)) do table.insert(items, note:item()) end
			local selected = self.selected and Notes:find(self.selected)
			if not selected then self.selected = nil end
			local open = 0
			for _, item in ipairs(items) do if item.icon == "circle" then open = open + 1 end end
			return {
				lists = {notes = items},
				loading = {notes = state.loading and #items == 0},
				draft = self.draft or "",
				summary = state.loading and "Loading…" or (#items == 0 and "No notes yet"
					or string.format("%d open of %d", open, #items)),
				hasSelection = selected ~= nil,
				selectedDone = selected and selected.done or false,
				failure = state.error,
			}
		end,
		setDraft = function(self, text) self.draft = text end,
		add = function(self)
			Routes.assert(Notes:create({list = self.params.list, title = self.draft or "", done = false}))
			self.draft = nil
		end,
		selectNote = function(self, _, _, row) self.selected = row and row.id end,
		toggle = function(self)
			local note = Routes.assert(self.selected and Notes:find(self.selected), "Choose a note.")
			Routes.assert(note:update({done = not note.done}))
		end,
		remove = function(self)
			local note = Routes.assert(self.selected and Notes:find(self.selected), "Choose a note.")
			note:delete()
			self.selected = nil
		end,
	},
	account = require("data.account").route({view = "pages/Account"}),
}
