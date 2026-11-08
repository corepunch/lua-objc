-- The fixture's one page of remote rows (tests/data_backend.test.lua).
local Items = require("tests.fixtures.backend.models.Items")

return {
	items = {
		view = "pages/Items",
		load = function(self) return Items:query({}, {order = "createdAt desc", limit = 50}) end,
		data = function(self, state)
			local titles = {}
			for _, item in ipairs(Items:select(nil, {order = "title"})) do table.insert(titles, item.title) end
			return {summary = state.loading and "Loading" or table.concat(titles, ", "), failure = state.error}
		end,
		add = function(self, title) return Items:create({title = title}) end,
		rename = function(self, id, title) Items:find(id):update({title = title}) end,
		remove = function(self, id) Items:find(id):delete() end,
	},
}
