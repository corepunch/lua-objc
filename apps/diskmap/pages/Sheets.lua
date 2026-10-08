-- The sheets of the window by route name, one route file each
-- (pages/sheets/). Each extends pages/SheetRoute.lua; the root controller
-- builds them with controllers/SheetController.lua.
local Routes = require("data.routes")

return Routes.include(
	"apps.diskmap.pages.sheets.History",
	"apps.diskmap.pages.sheets.Sdks",
	"apps.diskmap.pages.sheets.SnapshotChanges",
	"apps.diskmap.pages.sheets.Settings",
	"apps.diskmap.pages.sheets.Management",
	"apps.diskmap.pages.sheets.Onboarding",
	"apps.diskmap.pages.sheets.Tour"
)
