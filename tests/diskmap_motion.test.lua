_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Measurement and the map's change of level animate. Opening a page or
-- switching the map's style applies at once; sizes arriving from a scan
-- animate, and looking inside a group moves the rings to the new level.
local app = Controller.new(Mock.new())
app:createWindow()

local transactions = 0
local withAnimation = ns.withAnimation
ns.withAnimation = function(...) transactions = transactions + 1; return withAnimation(...) end

for _, id in ipairs({"map", "applications", "overview", "xcode", "overview"}) do app:show(id) end
t.assertEqual(transactions, 0, "switching pages does not animate")

app:show("map")
local rings = app.page.refs.sunburst.subviews[1]
app.page.template.actions.chartSelect("developer", 1)
t.assertEqual(app.pages.map.focus, "developer", "clicking a group still focuses it")
t.assertEqual(transactions, 1, "looking inside a group animates in one transaction")
t.expect(ns._sectorSceneTransitionState(rings) > 0, "which moves the rings to the new level")
local bridge = require("AppKitNative")
bridge._motionSettle()
t.assertEqual(ns._sectorSceneTransitionState(rings), 0, "settling the transaction ends their move")
app.page.template.actions.up()
t.assertEqual(transactions, 2, "so does going back out")
bridge._motionSettle()
-- Reduce Motion shows the new level at once.
bridge._motionOverrideReduceMotion(true)
app.page.template.actions.chartSelect("developer", 1)
t.assertEqual(ns._sectorSceneTransitionState(rings), 0, "Reduce Motion shows the new level without moving the rings")
app.page.template.actions.up()
bridge._motionOverrideReduceMotion(nil)
bridge._motionSettle()
transactions = 0
app.page.template.actions.style(1)
app.page.template.actions.style(0)
t.assertEqual(transactions, 0, "switching the map style does not animate")

app.scan:notify()
t.assertEqual(transactions, 1, "a scan update animates its new sizes")

ns.withAnimation = withAnimation
