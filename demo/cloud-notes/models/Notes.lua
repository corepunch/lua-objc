-- A note of one list. Rows are online, the signed-in person's alone; the
-- store holds those of the lists last shown.
local Model = require("data.model")

local Notes, Note = Model:extend("notes", {
	remote = "private",
	fields = {
		list = "string(32)",
		title = "string(255)",
		done = {"boolean?", default = false},
	},
	indexes = {{"list", "createdAt desc"}},
	constraints = {
		title = function(_, title)
			if type(title) ~= "string" or not title:match("%S") then return "A note needs some text." end
			if #title > 255 then return "A note is at most 255 characters." end
		end,
	},
})

-- The notes of `list`, open first, newest first within each.
function Notes:of(list)
	local notes = self:select({list = list}, {order = "createdAt desc"})
	local open, done = {}, {}
	for _, note in ipairs(notes) do table.insert(note.done and done or open, note) end
	for _, note in ipairs(done) do table.insert(open, note) end
	return open
end

-- What a list row shows: the note and its state as a symbol.
function Note:item()
	return {id = self.id, title = self.title, icon = self.done and "checkmark.circle.fill" or "circle"}
end

return Notes
