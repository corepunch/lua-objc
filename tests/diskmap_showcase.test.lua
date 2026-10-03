_G.__headless = true
local t = require("TestKit")
local Provider = require("apps.diskmap.services.Provider")
local Controller = require("apps.diskmap.Controller")

-- `--showcase` is the synthetic disk with presentable names for screenshots
-- and promotional captures: the same data, no "Mock" placeholders.
local showcase = Provider.select({[1] = "--showcase"})
t.expect(showcase.mock, "showcase runs on the virtual provider")
t.assertEqual(showcase.label, "Macintosh HD", "the showcase disk has an ordinary volume name")
t.assertEqual(showcase.badge, nil, "the showcase leaves the Mock HDD marker out")
t.assertEqual(showcase.home, "/Users/appleseed", "the showcase uses a neutral home folder")
local mock = Provider.select({[1] = "--mock"})
t.assertEqual(mock.badge, "Mock HDD", "--mock keeps marking the virtual disk")

local leaked = {}
for path in pairs(showcase.totals) do
	if path:find("[Mm]ock") then table.insert(leaked, path) end
end
t.assertEqual(#leaked, 0, "no measured path carries a Mock placeholder: " .. tostring(leaked[1]))
local discoveries
showcase.discoverEntries(showcase.home, function(entries) discoveries = entries end)
t.assertEqual(discoveries[1].path, "/Applications/Reel Studio.app", "showcase apps have presentable names")
t.expect(#discoveries == #(function() local d; mock.discoverEntries(mock.home, function(e) d = e end); return d end)(),
	"renaming keeps every discovered app")
local volumes
showcase.volumes(function(value) volumes = value end)
t.assertEqual(volumes.info.VolumeName, "Macintosh HD", "volume details use the showcase name")

local app = Controller.new(showcase)
local state = app:state()
t.assertEqual(state.volumeName, "Macintosh HD", "the page header names the showcase volume")
t.expect(not state.status:find("Mock HDD", 1, true), "the status line has no Mock HDD marker")
t.assertEqual(app.env.model.home, "/Users/appleseed", "catalog paths follow the virtual disk's home")
local window = app:createWindow()
t.assertEqual(window.title, "Diskmap", "the showcase window title has no Mock HDD marker")
app.env.scan:start()
local derived = app.env.model.measurements["derived"]
t.expect(derived ~= nil and (derived.bytes or 0) > 0, "catalog measurements match the virtual home folder")

-- `--map-style` picks the Map's initial chart.
local Routes = require("data.routes")
local function routePage(id, app) return Routes.page(require("apps.diskmap.routes")[id], {id = id}, app, "apps.diskmap") end
t.assertEqual(Provider.launch({[1] = "--map-style=rectangles"}).mapStyle, "rectangles", "the map style switch is read")
t.assertEqual(routePage("map", {mapStyle = "rectangles"}).style, "rectangles", "the map can open as rectangles")
t.assertEqual(routePage("map", {mapStyle = "hexagons"}).style, "rings", "unknown styles fall back to rings")
t.assertEqual(routePage("map", {}).style, "rings", "rings stay the default")

-- A capture plan switches the chart at runtime, as the segmented control does.
app:show("map")
app:show("map", {style = "rectangles"})
t.assertEqual(app.env:page("map").style, "rectangles", "setMapStyle switches the Map's chart")
t.expect(app.page.refs.treemap ~= nil, "the Map page redraws as a treemap")
app:show("map", {style = "rings"})
t.expect(app.page.refs.treemap == nil and app.page.refs.sunburst ~= nil, "and back to rings")
t.assertThrows(function() app:setMapStyle("hexagons") end, "an unknown map style is an error")
t.assertEqual(app.env:page("map").style, "rings", "a rejected style leaves the chart alone")

os.exit(t.summary() and 0 or 1)
