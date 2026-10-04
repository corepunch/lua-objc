local Flow = require("data.flow")
local Adventures = require("apps.adventure-arena.models.Adventures")

-- What a tap on a cover, a shelf or a story in progress does, shared by
-- every page that lists stories. `origin` names the navigation stack the
-- tap came from, so the page opens in the tab the reader is using.
local Opening = Flow:extend()

function Opening:game(id, origin)
	if not Adventures:find(id) then return false end
	self.app.focus(origin)
	self.app.push("detail", { id = id, origin = origin })
	return true
end

function Opening:collection(title, origin)
	if #Adventures:collection(title) == 0 then return false end
	self.app.focus(origin)
	self.app.push("collection", { title = title, origin = origin })
	return true
end

function Opening:story(id, origin, fresh)
	self.app.focus(origin)
	return self.app.openSession(id, fresh)
end

return Opening
