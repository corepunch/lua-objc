_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local PageController = require("data.pagecontroller")
local path = os.tmpname()
local file = assert(io.open(path .. ".etlua", "w"))
file:write('<Label id="value" text="<%= count %>" />'); file:close()
local presentations, count = {}, 0
local request = {view = path, queries = {inspect = true}}
function request:data() return {count = count, disabled = {increment = count > 0}} end
function request:increment() count = count + 1 end
function request:inspect() return count end
local page = PageController.new({page = {id = "example", title = "Example"}, request = request, ns = ns, viewsDir = "",
	presented = function(data) table.insert(presentations, {count = data.count, disabled = data.disabled.increment, title = data.page.title}) end})
page:mount(ns.VStack {}, {})
t.assertEqual(#presentations, 1, "mount explicitly presents the requested page data")
t.assertEqual(presentations[1].title, "Example", "the window receives page metadata")
t.assertEqual(presentations[1].count, 0, "initial presentation has initial data")
page.actions.increment()
t.assertEqual(#presentations, 2, "a page mutation presents its updated operations")
t.assertEqual(presentations[2].count, 1, "the window sees the new state")
t.expect(presentations[2].disabled, "native toolbar validation can follow page state")
t.assertEqual(page.actions.inspect(), 1, "queries still read normally")
t.assertEqual(#presentations, 2, "a query does not present or redraw the page")
page:dispose(); page:update({})
t.assertEqual(#presentations, 2, "a disposed page does no presentation work")
os.remove(path .. ".etlua")
os.exit(t.summary() and 0 or 1)
