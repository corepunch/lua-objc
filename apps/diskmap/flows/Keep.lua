local Keeps = require("apps.diskmap.models.Keeps")
local Flow = require("data.flow")

-- Keep: a location a person keeps out of every suggestion, in the store's
-- `kept` and saved through the app's service at once. A flow over a page or
-- the app (lua/data/flow.lua).
--
--   Keep(page):toggle("derived")   -> saved, and a message when saving failed
local Keep = Flow:extend()

function Keep:toggle(id)
	local ok, message = Keeps:toggle(id)
	if not ok then return false, message end
	if not self.app.service.saveKeep(Keeps:values()) then
		self.app.service.showError("Could not save Keep", "Keep preference could not be saved.")
		return false, "Keep preference could not be saved."
	end
	return true
end

return Keep
