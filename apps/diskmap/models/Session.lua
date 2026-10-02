local Model = require("data.model")

-- What the person is doing in the window, shared by every page: the text in
-- the toolbar's search field. Pages that filter by it need this model, so
-- typing rebinds exactly them.
local Session = Model.define({id = "session", schema = "Session"})

function Session.new()
	return setmetatable({query = ""}, Session)
end

function Session:setQuery(value)
	self.query = value or ""
end

return Session
