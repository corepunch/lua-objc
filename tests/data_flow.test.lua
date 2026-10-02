-- Lapis-style flows: action code shared by pages, forwarding to the page it wraps.
_G.__headless = true
local t = require("TestKit")
local Flow = require("data.flow")

local Marks = Flow:extend()
function Marks:markAll(items)
	for _, item in ipairs(items) do table.insert(self.app.marked, item) end
	self.count = #items
	return self:summary()
end

local page = {app = {marked = {}}, params = {source = "Files"}}
function page:summary() return #self.app.marked .. " from " .. self.params.source end

local marks = Marks(page)
t.assertEqual(marks:markAll({"a", "b"}), "2 from Files", "a flow reads the page's fields and runs its methods on the page")
t.assertEqual(#page.app.marked, 2, "it acts on what the page holds")
t.assertEqual(marks.count, 2, "what a flow assigns stays on the flow")
t.expect(rawget(page, "count") == nil, "and not on the page")
t.expect(Marks(marks)._ == page, "a flow of a flow wraps the same page")
local Extended = Marks:extend({extra = function() return "extra" end})
t.assertEqual(Extended(page):extra(), "extra", "a flow class extends another")
t.assertEqual(Extended(page):markAll({"c"}), "3 from Files", "and inherits its methods")
t.expect(not pcall(Marks, 42), "a flow wraps a table")

-- exposeAssigns writes what the flow assigns to the page.
local Selecting = Flow:extend({exposeAssigns = true})
function Selecting:choose(id) self.selected = id end
Selecting(page):choose("x")
t.assertEqual(page.selected, "x", "an exposing flow assigns to the page")

-- A page finds its app's flows by name.
local Routes = require("data.routes")
local Mark = Flow:extend()
function Mark:mark(item) table.insert(self.app.marked, item); return self.id end
package.preload["testapp.flows.Mark"] = function() return Mark end
local routed = Routes.page({view = "V"}, {id = "files", attrs = {}}, {marked = {}}, "testapp")
t.assertEqual(routed:flow("Mark"):mark("z"), "files", "self:flow(name) wraps the page in flows/<name>")
t.assertEqual(routed.app.marked[1], "z", "and acts on the page")
t.expect(not pcall(function() Routes.page({view = "V"}, {id = "x"}, {}):flow("Mark") end), "a page without an app module has no flows")

os.exit(t.summary() and 0 or 1)
