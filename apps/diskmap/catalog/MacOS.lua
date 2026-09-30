local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("macos", "macOS", "Required system, boot and recovery data", "apple.logo", "systemGray", {
	item("unix", "Unix system tools", "System executables and libraries", "/usr", system),
	item("root-system", "System root", "Remaining root files; mounted volumes are excluded", "/", system),
	item("system", "Operating system", "Protected macOS installation", "/System", system),
	-- Volumes are measured by their own APFS used space (`volume` names the
	-- role): Preboot's cloned files add up to several times what it holds,
	-- and Recovery is usually not mounted at all.
	item("preboot", "Preboot", "Boot support; never manually remove", "/System/Volumes/Preboot", D.with(system, {volume = "Preboot"})),
	item("recovery", "Recovery", "macOS recovery environment", "/System/Volumes/Recovery", D.with(system, {volume = "Recovery"})),
	item("update-volume", "Update volume", "Where macOS stages an update while preparing and installing it", "/System/Volumes/Update", D.with(system, {volume = "Update"})),
	item("vm", "Virtual memory", "Swap and system memory backing", "/System/Volumes/VM", D.with(system, {volume = "VM"})),
	require("apps.diskmap.catalog.Leftovers")(),
})
end
