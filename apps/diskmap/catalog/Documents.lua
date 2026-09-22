local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("documents", "Documents", "Personal documents, downloads and desktop files", "doc.fill", "systemGreen", {
	item("documents-user", "Documents", "Personal documents and projects", "~/Documents"),
	item("downloads", "Downloads", "Downloaded files, installers and archives", "~/Downloads"),
	item("desktop", "Desktop", "Files kept on your desktop", "~/Desktop"),
})
end
