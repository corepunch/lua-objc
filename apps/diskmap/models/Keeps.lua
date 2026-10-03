local Model = require("data.model")
local Keeps = Model:extend("keeps", {source = function()
	local rows = {}
	for id, kept in pairs(Model.db.kept or {}) do if kept then table.insert(rows, {id = id}) end end
	return rows
end})

function Keeps:valid(id)
	if type(id) ~= "string" then return false end
	local Locations = require("apps.diskmap.models.Locations")
	if Locations:find(id) then return true end
	local device = id:match("^simulator:(.+)$")
	if device then return device:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil end
	local path = id:match("^worktree:(/.+)$")
	if not path or path:find("%z") then return false end
	for part in path:gmatch("[^/]+") do if part == "." or part == ".." then return false end end
	return true
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
function Keeps:resourceCount()
	local Locations = require("apps.diskmap.models.Locations")
	local count = 0
	for _, keep in ipairs(self:all()) do if Locations:find(keep.id) then count = count + 1 end end
	return count
end

return Keeps
