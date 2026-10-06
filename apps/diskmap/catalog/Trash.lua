local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("trash", "Trash", "Space remains occupied until Trash is emptied in Finder", "trash", "systemGray", {
	item("user-trash", "Your Trash", "Review before permanently removing files", "~/.Trash", {nature = "personal", remover = "finder", action = "empty", threshold = 1e9, advice = "Items you moved to the Trash still take space until you empty it. Review them first: emptying permanently removes everything in Trash on all mounted volumes. This cannot be undone. Finder performs the deletion; Diskmap takes it out of its totals."}),
})
end
