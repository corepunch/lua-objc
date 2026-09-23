local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("applications", "Applications", "Installed apps; developer installations are counted under Developer", "app.fill", "systemBlue", {
	item("apps-builtin", "Built-in applications", "Applications supplied with macOS", "/System/Applications"),
	group("apps-system", "Installed applications", "Shared applications on this Mac", "app.fill", "systemBlue", {
		item("apps-system-other", "Other files in Applications", "Remaining files outside individually measured app bundles", "/Applications"),
	}),
	group("apps-user", "Personal applications", "Applications installed for your account", "app.fill", "systemBlue", {
		item("apps-user-other", "Other files in Applications", "Remaining files outside individually measured app bundles", "~/Applications"),
	}),
})
end
