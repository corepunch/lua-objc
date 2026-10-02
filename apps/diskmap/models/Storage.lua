local Model = require("data.model")
local Core = require("apps.diskmap.Model")

-- The storage inventory every page reads: the catalog of resources with their
-- measurements, the last scan's files and breakdowns, what is kept. It is a
-- graph model: whatever changes it (a scan tick, a mark, a setting) calls
-- `storage:changed()` and the pages that need it rebind. The domain functions
-- live in apps/diskmap/Model.lua and models/.
local Storage = Model.define({id = "storage"})

function Storage.new(_, services)
	local storage = Core.new(services.home)
	if services.mock then
		for _, row in ipairs(storage.resources:leaves()) do row.appIcon = nil end
	end
	local loadFolders = rawget(services.service, "loadFolders")
	storage.projectRoots = type(loadFolders) == "function" and loadFolders("projects") or {}
	return storage
end

return Storage
