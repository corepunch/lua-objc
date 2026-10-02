local Model = require("data.model")
local Flow = require("data.flow")
local Locations = require("apps.diskmap.models.Locations")
local Constraints = require("apps.diskmap.helpers.Constraints")

-- Keep: a location a person keeps out of every suggestion, in the store's
-- `kept` and saved through the app's service at once. A flow over a page or
-- the app (lua/data/flow.lua).
--
--   Keep(page):toggle("derived")   -> saved, and a message when saving failed
local Keep = Flow:extend()

function Keep:toggle(id)
	local ok, err = Constraints.evaluate("keep", {row = Locations:find(id)})
	if not ok then return false, err and err.message end
	local kept = Model.db.kept
	kept[id] = not kept[id] or nil
	local save = self.app.service.saveKeep
	if save and not save(kept) then return false, "Keep preference could not be saved." end
	return true
end

return Keep
