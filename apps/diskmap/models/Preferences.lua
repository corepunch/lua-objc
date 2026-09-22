local Constraints = require("apps.diskmap.models.Constraints")
local Preferences = {}
function Preferences.toggle(model, id)
	local ok, err = Constraints.evaluate("keep", {row = model.resources:find(id)})
	if not ok then return false, err end
	model.kept[id] = not model.kept[id] or nil
	return true
end
return Preferences
