local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("other", "Other files", "Measured files outside recognized locations", "folder.fill", "systemBrown", {
	item("home-other", "Other home files", "Files and folders outside the named home categories", "~"),
	item("opt-other", "Other optional software", "Optional software outside known package managers", "/opt"),
})
end
