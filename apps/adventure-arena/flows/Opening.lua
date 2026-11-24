local Flow = require("data.flow")
local Adventures = require("apps.adventure-arena.models.Adventures")

-- What a tap on a cover, a shelf or a story in progress does, shared by
-- every page that lists stories.
local Opening = Flow:extend()

function Opening:game(id)
	if not Adventures:find(id) then return false end
	self.app.push("detail", { id = id })
	return true
end

function Opening:collection(title)
	if #Adventures:collection(title) == 0 then return false end
	self.app.push("collection", { title = title })
	return true
end

function Opening:story(id, fresh)
	return self.app.openSession(id, fresh)
end

return Opening
