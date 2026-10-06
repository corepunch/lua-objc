_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Nothing in the app animates the view tree: there is no transaction engine,
-- so a scan tick (many a second) or a page change cannot diff the layout of
-- the page and start animations while the user scrolls. Charts show final
-- geometry immediately; the welcome tour uses the system's push transition.
t.assertEqual(ns.withAnimation, nil, "the framework has no animation transactions")
t.assertEqual(ns.transition, nil, "and no per-view transitions")

local app = Controller.new(Mock.new())
app:createWindow()
for _, id in ipairs({"map", "applications", "overview", "xcode", "overview"}) do app:show(id) end

app:show("map")
local rings = app.page.refs.sunburst
app.page.actions.chartSelect("developer", 1)
t.assertEqual(app.env:page("map").focusId, "developer", "clicking a group still focuses it")
t.expect(app.page.refs.sunburst ~= rings, "drilling creates fresh chart elements")
local inside = app.page.refs.sunburst
app.page.actions.up()
t.expect(app.page.refs.sunburst ~= rings and app.page.refs.sunburst ~= inside, "going back builds fresh chart elements")
t.assertEqual(rings.superview, nil, "the old chart is detached")
t.assertEqual(app.page.refs.sunburst.subviews[1].layer.animationKeys, nil, "the chart has no layer animations")
local previous, previousChart = app.page, app.page.refs.sunburst
app:show("overview")
t.assertEqual(previous.refs, nil, "navigation disposes the old page refs")
t.assertEqual(previous.template, nil, "navigation disposes its template and callbacks")
app:show("map")
t.expect(app.page ~= previous, "returning creates a new page controller")
t.expect(app.page.refs.sunburst ~= previousChart, "returning creates new native chart elements")
t.assertEqual(app.pages, nil, "the root has no page-controller cache")
local mounted = app.page
local mountedChart = mounted.refs.sunburst
-- A new argument for the page showing focuses it in place, as a browser
-- follows a link within one document; the chart draws the new level.
app:show("map", {focus = "developer"})
t.expect(app.page == mounted, "a new route argument keeps the page showing")
t.expect(app.page.refs.sunburst ~= mountedChart and mountedChart.superview == nil, "and draws fresh chart elements for it")
t.assertEqual(app:location(), "/map/developer", "the location names the argument")
app:show("overview")
local beforeBack = app.page.refs.chart
t.expect(app.navigation:back(), "Back navigates to the previous destination")
t.expect(app.page.refs.sunburst ~= mountedChart, "Back builds a fresh map")
t.expect(app.navigation:forward(), "Forward returns to Overview")
t.expect(app.page.refs.chart ~= beforeBack, "Forward builds a fresh overview")
app:show("map", {focus = ""})

app.env.scan:notify()
t.expect(app.page ~= nil, "a scan update applies at once")

-- Pointing at a resource selects; it does not change level.
app.page.actions.chartHover("developer")
t.assertEqual(app.env:page("map").selectedId, nil, "hover points at the list without changing the kept selection")
t.assertEqual(app.env:page("map").focusId, "", "hovering does not look inside a group")
os.exit(t.summary() and 0 or 1)
