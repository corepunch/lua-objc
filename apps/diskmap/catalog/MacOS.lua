local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("macos", "macOS", "Required system, boot and recovery data", "shield.fill", "systemGray", {
	item("unix", "Unix system tools", "System executables and libraries", "/usr", system),
	item("root-system", "System root", "Remaining root files; mounted volumes are excluded", "/", system),
	item("system", "Operating system", "Protected macOS installation", "/System", system),
	item("preboot", "Preboot", "Boot support; never manually remove", "/System/Volumes/Preboot", system),
	item("recovery", "Recovery", "macOS recovery environment", "/System/Volumes/Recovery", system),
	item("vm", "Virtual memory", "Swap and system memory backing", "/private/var/vm", system),
})
end
