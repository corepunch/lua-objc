local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("trash", "Trash", "Space remains occupied until Trash is emptied in Finder", "trash", "systemGray", {
	item("user-trash", "Your Trash", "Review before permanently removing files", "~/.Trash", {action = "empty", consequence = "Permanently removes everything in Trash on all mounted volumes. This cannot be undone. Finder performs the deletion; Diskmap remeasures afterward."}),
})
end
