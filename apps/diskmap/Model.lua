local Catalog = require("apps.diskmap.Catalog")
local Model = {}
function Model.size(bytes)
	if bytes == nil then return "Not measured" end
	if bytes >= 1e9 then return string.format("%.1f GB", bytes / 1e9) end
	if bytes >= 1e6 then return string.format("%.1f MB", bytes / 1e6) end
	return string.format("%.0f KB", bytes / 1000)
end
function Model.new(home)
	local self = {home = home, includeMedia = false, tree = Catalog.tree(home), byId = {}, leaves = {}, measurements = {}, kept = {}, scan = {}}
	local function index(rows, parent)
		for _, row in ipairs(rows) do
			row.parentId = parent and parent.id
			row.icon = row.icon or parent and parent.icon or "doc"
			row.color = row.color or parent and parent.color or "systemGray"
			row.appIcon = row.appIcon or parent and parent.appIcon
			self.byId[row.id] = row
			if row.children then index(row.children, row) else
				self.leaves[#self.leaves + 1] = row
				if row.mediaAccess then self.measurements[row.id] = {status = "excluded"} end
				if row.measurement then self.measurements[row.id] = {status = row.measurement} end
			end
		end
	end
	index(self.tree)
	return self
end
function Model.total(model)
	local bytes = 0; for _, m in pairs(model.measurements) do bytes = bytes + (m.bytes or 0) end
	return bytes
end
return Model
