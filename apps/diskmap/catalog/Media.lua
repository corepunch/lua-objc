local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("media", "Photos & media", "Libraries and local media; manage library contents in their apps", "photo.fill", "systemOrange", {
	item("pictures", "Photos & pictures", "Photo libraries and image files", "~/Pictures", {mediaAccess = true}),
	item("music", "Music & audio", "Music libraries, recordings and projects", "~/Music", {mediaAccess = true}),
	item("movies", "Movies & video", "Video libraries and creative projects", "~/Movies", {mediaAccess = true}),
})
end
