local D = require("apps.diskmap.catalog.Definitions")
local item, group, cache, xcode, system, assets, tool = D.item, D.group, D.cache, D.xcode, D.system, D.assets, D.tool
return function()
	return group("backups", "Backups", "Local snapshots are personal restore points", "clock.arrow.circlepath", "systemTeal", {
	{id = "snapshots", name = "Local snapshots", subtitle = "Managed by Time Machine; file scans cannot measure exclusive allocation", icon = "clock.arrow.circlepath", policy = "System managed", action = "settings", measurement = "unsupported"},
})
end
