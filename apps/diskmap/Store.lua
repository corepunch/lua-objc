local Model = require("data.model")

-- Diskmap's store: the tables its models read (lua/data/model.lua). The
-- sources fill `items`, the person's flags are `marks`, Keep is `kept`;
-- nothing else holds Diskmap's state.
--
--   home             the home folder
--   items            every measured row, by id (models/Items.lua)
--   marks            what is flagged for review, by path (models/Marks.lua)
--   kept             item ids a person keeps out of suggestions (models/Keeps.lua)
--   scan             {generation, running, status, pending}: the measurement in progress
--   folders          project folders the person added
--   disk             {freeKb, totalKb} of the startup disk, refreshed after a change
--   capacity         {total, available} of the startup volume
--   installedApplications   the apps Spotlight knows, once read, for owner inference
local Store = {}

function Store.new(home)
	return Model.bind({home = home, items = {}, marks = {}, kept = {}, folders = {},
		scan = {generation = 0, running = false, status = "", pending = {}}})
end

return Store
