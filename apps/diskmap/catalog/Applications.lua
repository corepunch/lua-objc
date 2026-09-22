local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("applications", "Applications", "Installed apps; developer installations are counted under Developer", "app.fill", "systemBlue", {
	item("apps-builtin", "Built-in applications", "Applications supplied with macOS", "/System/Applications"),
	item("apps-system", "Installed applications", "Shared applications on this Mac", "/Applications"),
	item("apps-user", "Personal applications", "Applications installed for your account", "~/Applications"),
})
end
