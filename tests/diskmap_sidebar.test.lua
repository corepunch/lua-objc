_G.__headless = true
local t = require("TestKit")
local bridge = require("AppKitNative")
local Model = require("apps.diskmap.Model")
local Developer = require("apps.diskmap.models.Developer")
local Navigation = require("apps.diskmap.controllers.NavigationController")

-- Diskmap is for everyone (#52): developer pages follow the system pages,
-- and appear only on a Mac with developer data.
local order = {}
for _, row in ipairs(Navigation.destinations) do if row.section then table.insert(order, row.title) end end
t.assertEqual(table.concat(order, ","), "Storage,Clean Up,System,Developer,Learn", "Developer comes after System")

local model = Model.new("/Users/test")
t.expect(not Developer.present(model, function() return false end), "a Mac without developer folders has no Developer section")
t.expect(Developer.present(model, function(path) return path == "/Users/test/Library/Developer" end), "~/Library/Developer shows it")
t.expect(Developer.present(model, function(path) return path == "/Applications/Xcode.app" end), "Xcode shows it")
model.measurements.derived = {status = "complete", bytes = 900e6}
t.expect(Developer.present(model, nil), "measured developer data shows it")

local shown
local navigation = Navigation.new(function(id) shown = id end)
local plain = #navigation:list()
t.expect(navigation:setSectionVisible("Developer", false), "the section can be hidden")
t.assertEqual(#navigation:list(), plain - 5, "hiding removes the header and its four pages")
for _, row in ipairs(navigation:list()) do t.expect(row.id ~= "xcode" and row.title ~= "Developer", "no developer row remains") end
t.expect(not navigation:setSectionVisible("Developer", false), "hiding twice changes nothing")
t.expect(navigation:setSectionVisible("Developer", true), "it comes back")
t.assertEqual(#navigation:list(), plain, "all rows return")

-- The app hides it on a Mac without developer data.
local Controller = require("apps.diskmap.Controller")
local service = {monitor = function() end, start = function() return {} end, await = function() end, cancel = function() end,
	diskSpace = function() return {totalKb = 10000, freeKb = 5000} end, exists = function() return false end}
local app = Controller.new(service)
app:createWindow()
local sidebar = app.navigation.refs.sidebar
t.assertEqual(sidebar.rowCount, plain - 5, "an ordinary Mac's sidebar has no Developer section")
app.model.measurements.derived = {status = "complete", bytes = 900e6}
app:updateRows()
t.assertEqual(sidebar.rowCount, plain, "the section appears once developer data is measured")
t.assertEqual(bridge._tableCell(sidebar, 0, app.navigation:index("developer") - 1).textField.stringValue, "Developer", "under its own header")

os.exit(t.summary() and 0 or 1)
