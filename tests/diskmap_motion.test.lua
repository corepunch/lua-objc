_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Nothing in the app animates the view tree: there is no transaction engine,
-- so a scan tick (many a second) or a page change cannot diff the layout of
-- the page and start animations while the user scrolls. Only an Arc animates
-- its own path, and the welcome tour uses the system's push transition.
t.assertEqual(ns.withAnimation, nil, "the framework has no animation transactions")
t.assertEqual(ns.transition, nil, "and no per-view transitions")

local app = Controller.new(Mock.new())
app:createWindow()
for _, id in ipairs({"map", "applications", "overview", "xcode", "overview"}) do app:show(id) end

app:show("map")
local rings = app.page.refs.sunburst
app.page.template.actions.chartSelect("developer", 1)
t.assertEqual(app.pages.map.focus, "developer", "clicking a group still focuses it")
t.expect(app.page.refs.sunburst == rings, "drilling keeps the chart view")
app.page.template.actions.up()
t.expect(app.page.refs.sunburst == rings, "and so does going back out")

app.scan:notify()
t.expect(app.page ~= nil, "a scan update applies at once")

-- Pointing at a resource selects; it does not change level.
app.page.template.actions.chartHover("developer")
t.assertEqual(app.pages.map.selectedId, "developer", "map hover and the list share one token")
t.assertEqual(app.pages.map.focus, "", "hovering does not look inside a group")
os.exit(t.summary() and 0 or 1)
