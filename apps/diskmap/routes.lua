-- Every page and sheet of Diskmap by route name (lua/data/routes.lua), as
-- Lapis gathers an application's sub-applications. app.xml names the route
-- of each page; the root controller builds the sheets from pages/Sheets.lua.
local Routes = require("data.routes")

return Routes.include(
	"apps.diskmap.pages.Overview",
	"apps.diskmap.pages.Applications",
	"apps.diskmap.pages.Files",
	"apps.diskmap.pages.Duplicates",
	"apps.diskmap.pages.Projects",
	"apps.diskmap.pages.Simulators",
	"apps.diskmap.pages.Worktrees",
	"apps.diskmap.pages.Explore",
	"apps.diskmap.pages.Folder",
	"apps.diskmap.pages.System",
	"apps.diskmap.pages.Developer",
	"apps.diskmap.pages.Learn",
	"apps.diskmap.pages.Search"
)
