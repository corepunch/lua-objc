local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("photos", "Photos", "The Photos library and other pictures. Manage the library in Photos.", "photo.fill", "systemOrange", {
		item("pictures", "Pictures", "Photo libraries and image files", "~/Pictures", {mediaAccess = true}),
	})
end
