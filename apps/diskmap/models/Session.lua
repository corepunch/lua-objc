local Model = require("data.model")
local Session = Model:extend("session")

function Session:current()
	return self:find("window") or self:create({id = "window", monitorEnabled = true, historyEnabled = false})
end

return Session
