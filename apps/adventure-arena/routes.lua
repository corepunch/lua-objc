-- Every page of Adventure Arena by route name (lua/data/routes.lua). app.xml
-- names the pages; controllers/PageHost.lua draws each one from its route in
-- the tab or navigation stack the root controller gives it.
local Routes = require("data.routes")

return Routes.include(
	"apps.adventure-arena.pages.Discover",
	"apps.adventure-arena.pages.Bookshelf",
	"apps.adventure-arena.pages.Search",
	"apps.adventure-arena.pages.Settings",
	"apps.adventure-arena.pages.Detail",
	"apps.adventure-arena.pages.Collection"
)
