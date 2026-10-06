local D = require("apps.diskmap.catalog.Definitions")
local Filesystem = require("apps.diskmap.knowledge.Filesystem")
-- Where interrupted updates, installs and crashes leave data behind, taken
-- from the locations knowledge/Filesystem marks `leftover`. Each becomes a
-- resource with the map's explanation, so a half-finished update shows up
-- in Clean Up once it passes its threshold, under the remover the map names
-- (a restart, the pending update, or Finder), with the map's advice.
return function()
	local children = {}
	for _, area in ipairs(Filesystem.areas) do
		for _, location in ipairs(area.locations) do
			local leftover = location.leftover
			if leftover then
				table.insert(children, (D.item(leftover.id, location.name, location.what, location.path,
					{nature = "leftover", remover = leftover.remover, threshold = leftover.threshold, advice = leftover.advice})))
			end
		end
	end
	return D.group("leftovers", "Update & install leftovers", "Where interrupted updates, installs and crashes leave data", "arrow.uturn.backward.circle.fill", "systemOrange", children)
end
