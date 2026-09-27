_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")

-- Only measurement animates. Opening a page, drilling into the map or
-- switching its style applies at once; sizes arriving from a scan animate.
local app = Controller.new(Mock.new())
app:createWindow()

local transactions = 0
local withAnimation = ns.withAnimation
ns.withAnimation = function(...) transactions = transactions + 1; return withAnimation(...) end

for _, id in ipairs({"map", "applications", "overview", "xcode", "overview"}) do app:show(id) end
t.assertEqual(transactions, 0, "switching pages does not animate")

app:show("map")
app.page.template.actions.chartSelect("developer", 1)
t.assertEqual(app.pages.map.focus, "developer", "clicking a group still focuses it")
app.page.template.actions.style(1)
app.page.template.actions.up()
app.page.template.actions.style(0)
t.assertEqual(transactions, 0, "drilling and switching the map style do not animate")

app.scan:notify()
t.assertEqual(transactions, 1, "a scan update animates its new sizes")

ns.withAnimation = withAnimation
