local Catalog = require("apps.diskmap.Catalog")
local Resources = require("apps.diskmap.models.Resources")
local Model = {}
function Model.size(bytes)
	if bytes == nil then return "Not measured" end
	if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
	if bytes >= 1e6 then return string.format("%.1f MB", bytes / 1e6) end
	return string.format("%.0f KB", bytes / 1000)
end
function Model.new(home)
	local self = {home = home, includeMedia = false, measurements = {}, kept = {}, scan = {}}
	local resources, err = Resources.new(self, Catalog.tree(home))
	assert(resources, err and err.message or "Could not build Diskmap resources")
	self.resources = resources
	for _, row in ipairs(resources:leaves()) do
		if row.mediaAccess then self.measurements[row.id] = {status = "excluded"} end
		if row.measurement then self.measurements[row.id] = {status = row.measurement} end
	end
	return self
end
function Model.total(model)
	local bytes = 0; for _, m in pairs(model.measurements) do bytes = bytes + (m.bytes or 0) end
	return bytes
end
return Model
