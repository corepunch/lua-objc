-- Every screen is a manifest route mounted in the window with page history.
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
	"apps.diskmap.pages.Search",
	"apps.diskmap.pages.Basket",
	"apps.diskmap.pages.History",
	"apps.diskmap.pages.Settings",
	"apps.diskmap.pages.SnapshotChanges",
	"apps.diskmap.pages.Sdks",
	"apps.diskmap.pages.Tour",
	"apps.diskmap.pages.Onboarding"
)
