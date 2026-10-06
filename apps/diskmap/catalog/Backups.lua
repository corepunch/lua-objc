local D = require("apps.diskmap.catalog.Definitions")
local item, group = D.item, D.group
return function()
	return group("backups", "Backups", "Local snapshots are personal restore points", "clock.arrow.circlepath", "systemTeal", {
	{id = "snapshots", name = "Local snapshots", subtitle = "Managed by Time Machine; file scans cannot measure exclusive allocation", icon = "clock.arrow.circlepath", nature = "system", remover = "none", action = "settings", measurement = "unsupported"},
})
end
