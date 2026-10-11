-- Every screen is a manifest route mounted in the window with page history.
local Routes = require("data.routes")

return Routes.include(
	"apps.diskmap.pages.Overview",
	"apps.diskmap.pages.Category",
	"apps.diskmap.pages.Folder",
	"apps.diskmap.pages.History"
)
