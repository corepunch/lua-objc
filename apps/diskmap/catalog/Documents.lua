local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("documents", "Documents", "Personal documents, downloads and desktop files", "doc.fill", "systemGreen", {
	item("documents-user", "Documents", "Personal documents and projects", "~/Documents", {nature = "personal"}),
	item("downloads", "Downloads", "Downloaded files, installers and archives", "~/Downloads",
		{nature = "personal", remover = "finder", threshold = 2e9, advice = "Review downloaded installers and archives in Finder. Keep personal files and anything you cannot download again."}),
	item("desktop", "Desktop", "Files kept on your desktop", "~/Desktop", {nature = "personal"}),
})
end
