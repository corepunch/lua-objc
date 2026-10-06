local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("applications", "Applications", "Installed apps; developer installations are counted under Developer", "app.fill", "systemBlue", {
	item("apps-builtin", "Built-in applications", "Applications supplied with macOS", "/System/Applications"),
	group("apps-system", "Installed applications", "Shared applications on this Mac", "app.fill", "systemBlue", {
		item("apps-system-other", "Other files in Applications", "Remaining files outside individually measured app bundles", "/Applications"),
	}),
	group("apps-user", "Personal applications", "Applications installed for your account", "app.fill", "systemBlue", {
		item("apps-user-other", "Other files in Applications", "Remaining files outside individually measured app bundles", "~/Applications"),
	}),
}, {page = "applications"})
end
