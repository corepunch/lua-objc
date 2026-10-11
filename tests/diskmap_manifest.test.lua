_G.__headless = true
local t = require("TestKit")
local Manifest = require("data.manifest")
local Routes = require("data.routes")
local Navigation = require("apps.diskmap.controllers.NavigationController")

-- The manifest (app.xml): few pages, each with a route and a view, the
-- sidebar as VISION.md draws it.
local manifest = Manifest.load("apps/diskmap/app.xml")
local routes = require("apps.diskmap.routes")
t.assertEqual(manifest.startup, "overview", "the app opens on the Overview")
for _, entry in ipairs(manifest.order) do
	local route = Routes.find(routes, entry)
	t.expect(route ~= nil, entry.id .. " has a route")
	local file = io.open("apps/diskmap/views/" .. route.view .. ".etlua")
	t.expect(file ~= nil, entry.id .. " has a view")
	if file then file:close() end
end
local listed = {}
for _, row in ipairs(Navigation.destinations) do if row.id then table.insert(listed, row.id) end end
t.assertEqual(table.concat(listed, " "), "overview xcode simulators projects worktrees packages editors ai system", "the sidebar leads with Overview, then the sources")
t.assertEqual(Navigation.destinations[2].title, "Sources", "the sources sit under one header")
t.assertEqual(#manifest.order, 11, "eleven pages in all, two of them unlisted")
t.expect(manifest.pages.folder.attrs.arg == "path", "the Folder Map carries its folder in its location")
local keys = {}
for _, entry in ipairs(manifest.order) do if entry.key then t.expect(not keys[entry.key], "key " .. entry.key .. " is used once"); keys[entry.key] = true end end

os.exit(t.summary() and 0 or 1)
