local Model = require("data.model")

-- Keep: the item ids a person keeps out of every suggestion, in the store's
-- `kept`. An id is an item's id (models/Items.lua), so a kept simulator or
-- worktree stays kept across measurements.
local Keeps = Model:extend("keeps", {source = function()
	local rows = {}
	for id, kept in pairs(Model.db.kept or {}) do if kept then table.insert(rows, {id = id}) end end
	return rows
end})

function Keeps:valid(id)
	return type(id) == "string" and id ~= "" and not id:find("%z")
end

function Keeps:restore(values)
	Model.db.kept = {}
	for id, kept in pairs(values or {}) do if kept == true and self:valid(id) then Model.db.kept[id] = true end end
end

function Keeps:toggle(id)
	if not self:valid(id) then return false, "Unknown Keep target." end
	Model.db.kept[id] = not Model.db.kept[id] or nil
	return true
end

function Keeps:values() return Model.db.kept end
function Keeps:contains(id) return Model.db.kept[id] == true end

return Keeps
