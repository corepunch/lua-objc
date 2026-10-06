-- The one screen: English in, Russian out as the person types. Every
-- keystroke is an action that translates (the service re-translates only
-- the line that changed); the editor keeps its caret because a page drawn
-- with the text it already shows leaves it alone.
return {
	translate = {
		view = "pages/Translate",
		queries = { copy = true },
		init = function(self) self.text, self.russian = "", "" end,
		data = function(self)
			return { text = self.text, russian = self.russian, failure = self.failure }
		end,
		edit = function(self, text)
			self.text = tostring(text or "")
			local russian, err = self.app.translator:translate(self.text)
			self.russian, self.failure = russian or "", err
		end,
		clear = function(self) self.text, self.russian, self.failure = "", "", nil end,
		copy = function(self) if self.russian ~= "" then self.app.clipboard.copy(self.russian) end end,
	},
}
