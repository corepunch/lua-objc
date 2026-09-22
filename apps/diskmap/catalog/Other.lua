local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("other", "Other files", "Measured files outside recognized locations", "folder.fill", "systemBrown", {
	item("home-other", "Other home files", "Files and folders outside the named home categories", "~"),
	item("users-other", "Other users & shared files", "Accessible files outside your home folder", "/Users"),
	item("opt-other", "Other optional software", "Optional software outside known package managers", "/opt"),
})
end
