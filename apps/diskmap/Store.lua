local Model = require("data.model")
local Catalog = require("apps.diskmap.Catalog")
local Locations = require("apps.diskmap.models.Locations")

-- Diskmap's store: the tables its models read (lua/data/model.lua), built
-- from the catalog for one home folder. A scan, the services and the pages
-- fill and change it; nothing else holds Diskmap's state.
--
--   home, includeMedia    the folder measured and whether media libraries are
--   locations             the catalog's locations (models/Locations.lua)
--   measurements          a location's size by its id: {status, bytes, ...}
--   kept                  ids a person keeps out of suggestions
--   scan, files           the running or last scan and the files it ranked
--   breakdowns            a location's immediate children, by its id
local Store = {}

-- A new store for `home`, bound as the one every model reads: an app builds
-- one per window, and a test builds the one it checks.
function Store.new(home)
	local db = Model.bind({home = home, includeMedia = false, measurements = {}, kept = {}, scan = {}, breakdowns = {}})
	local locations, err = Locations.seed(db, Catalog.tree(home))
	assert(locations, err and err.message or "Could not build Diskmap locations")
	for _, row in ipairs(Locations:leaves()) do
		if row.mediaAccess then db.measurements[row.id] = {status = "excluded"} end
		if row.measurement then db.measurements[row.id] = {status = row.measurement} end
	end
	return db
end

return Store
