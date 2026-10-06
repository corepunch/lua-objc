local D = require("apps.diskmap.catalog.Definitions")
local item, group, system = D.item, D.group, D.system
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
	item("vm", "Virtual memory", "Swap and system memory backing; a restart releases it", "/System/Volumes/VM",
		D.with(system, {volume = "VM", remover = "restart", threshold = 4e9, advice = "Swap files macOS pages memory out to under memory pressure. Quit memory-hungry apps or restart to release it; never delete swap files by hand."})),
	require("apps.diskmap.catalog.Leftovers")(),
})
end
