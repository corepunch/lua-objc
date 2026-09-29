-- demo/notes: queries, selection and search, the three-column window, and
-- the workspace split widths it relies on (sidebarWidth with a detail pane,
-- contentWidth for the middle column).
_G.__headless = true

local t = require("TestKit")
local ns = require("AppKit")
local function width(view) return view.frame.size.width end
local Model = require("demo.notes.Model")
local Controller = require("demo.notes.Controller")

local model = Model.new()
t.assertEqual(#model:visible(), 7, "every note is listed")
t.assertEqual(#model:favorites(), 3, "three sample notes are favorites")
t.assertEqual(model:note().title, "Launch plan", "the first note starts selected")
model:select(3)
t.assertEqual(model:note().title, "Weekend in Lisbon", "selecting shows another note")
model:select(99)
t.assertEqual(model.selected, 3, "an unknown note keeps the selection")
model:search("miso")
t.assertEqual(#model:visible(), 1, "search matches titles")
model:search("TRAM 28")
t.assertEqual(model:visible()[1].title, "Weekend in Lisbon", "search matches bodies, ignoring case")
model:search("")
t.assertEqual(#model:visible(), 7, "an empty search shows everything")
t.assertEqual(model:visible()[1].snippet:sub(1, 8), "Ship the", "rows carry the first paragraph as a snippet")
local folders = model:folders()
t.expect(folders[1].section, "folders sit under a section header")
t.assertEqual(folders[2].badge, "7", "All Notes counts every note")
t.assertEqual(Model.new({}):note(), nil, "an empty notebook selects nothing")

local controller = Controller.new()
controller:createWindow()
local refs = controller.content.refs
t.expect(refs.favorites ~= nil and refs.notes ~= nil, "the content has #favorites and #notes for reel captures")
t.expect(controller.detail.refs.body ~= nil, "the detail shows the note body")
local folderWidth = width(controller.content.refs.notes)
t.expect(math.abs(folderWidth - 330) <= 2, "contentWidth sets the middle column (got " .. folderWidth .. ")")
controller:search("aubergine")
t.assertEqual(#controller.model:visible(), 1, "the search field filters the list")
controller:select(4)
t.assertEqual(controller.detail.refs.noteTitle.stringValue, "Miso glazed aubergine", "selecting a row shows its note")

-- A fixed detail pane no longer moves the sidebar divider.
local sidebar = ns.VStack {}
local detail = ns.VStack {}
local window = ns.Window { title = "Split", width = 1000, height = 600, sidebar = sidebar, content = ns.VStack {},
	detail = detail, sidebarWidth = 200, detailWidth = 300 }
t.expect(math.abs(width(sidebar) - 200) <= 2, "sidebarWidth holds beside a fixed detail pane")
t.expect(math.abs(width(detail) - 300) <= 2, "detailWidth sizes the detail pane")
window:close()

os.exit(t.summary() and 0 or 1)
