_G.__headless = true
local t = require("TestKit")
local ns = require("AppKit")
local xml = require("ui.xml")

-- Rows drag as their files (SwiftUI `.draggable`).
local view, refs = xml.render([[<VStack>
  <List id="files" dragKey="path"><Column id="name" title="Name" /></List>
  <List id="plain"><Column id="name" title="Name" /></List>
</VStack>]], {actions = {}}, ns)
refs.files:replaceRows({{id = "a", name = "A", path = "/tmp/a.txt"}, {id = "b", name = "B"}})
refs.plain:replaceRows({{id = "a", name = "A", path = "/tmp/a.txt"}})
t.assertEqual(ns._tableDragPath(refs.files, 1), "/tmp/a.txt", "a row drags the file at its dragKey")
t.assertEqual(ns._tableDragPath(refs.files, 2), nil, "a row without a path does not drag")
t.assertEqual(ns._tableDragPath(refs.plain, 1), nil, "lists without dragKey do not drag")
t.expect(view ~= nil, "lists render")

-- Stacks take dropped files (SwiftUI `.dropDestination`).
local dropped
local target, targetRefs = xml.render('<VStack id="zone" onDrop="drop"><Label text="Drop here" /></VStack>',
	{actions = {drop = function(paths) dropped = paths; return #paths == 2 end}}, ns)
t.expect(ns._dropFiles(targetRefs.zone, {"/tmp/x", "/tmp/y"}), "the drop handler accepts files")
t.expect(dropped and dropped[1] == "/tmp/x" and dropped[2] == "/tmp/y", "dropped paths reach the handler in order")
t.expect(not ns._dropFiles(targetRefs.zone, {"/tmp/x"}), "the handler decides whether it took the files")
t.expect(target ~= nil, "drop targets render")
t.expect(not pcall(xml.render, '<VStack onDrop="missing" />', {actions = {}}, ns), "a misspelt drop action fails at render time")

-- Chart marks drag as files and take keyboard focus.
local focused, activated, went
local chart = xml.render([[<Treemap id="map" width="200" height="120" onSelect="select" onHover="hover" onBack="back" dragItem="drag">
  <TreemapNode id="apps" value="8" label="Applications" color="systemBlue" />
  <TreemapNode id="docs" value="3" label="Documents" color="systemGreen" />
  <TreemapNode id="music" value="1" label="Music" color="systemPink" />
</Treemap>]], {actions = {
	select = function(id, count) activated = {id, count} end,
	hover = function(id) focused = id end,
	back = function() went = true end,
	drag = function(id) return "/Users/test/" .. id end,
}}, ns)
chart.size = ns.Size(200, 120)
t.assertEqual(ns._pointerSend(chart, "drag", 10, 10), "/Users/test/apps", "dragging a cell drags its file")
t.expect(ns._pointerSend(chart, "key", "tab") and focused == "apps", "tab focuses the largest mark")
ns._pointerSend(chart, "key", "tab")
t.assertEqual(focused, "docs", "tab again moves to the next largest")
ns._pointerSend(chart, "key", "return")
t.expect(activated and activated[1] == "docs" and activated[2] == 2, "return opens the focused mark")
ns._pointerSend(chart, "key", "m"); ns._pointerSend(chart, "key", "u")
t.assertEqual(focused, "music", "typing filters and focuses the largest match")
ns._pointerSend(chart, "key", "escape")
ns._pointerSend(chart, "key", "delete")
t.expect(went, "delete with no filter goes up a level")
t.expect(not ns._pointerSend(chart, "key", "\t\1"), "unknown keys pass through")

-- The shared navigation logic.
local Keys = require("ui.chartkeys")
local moved = {}
local keys = Keys.new({{id = "a", value = 1, label = "Alpha"}, {id = "b", value = 5, label = "Beta"},
	{id = "b1", parent = "b", value = 2, label = "Beta one"}}, {focus = function(id) table.insert(moved, id) end})
keys:handle("right")
t.assertEqual(keys.focus, "b", "the first key focuses the largest top-level mark")
keys:handle("down")
t.assertEqual(keys.focus, "b1", "down enters the largest child")
keys:handle("up")
t.assertEqual(keys.focus, "b", "up returns to the parent")
keys:handle("right")
t.assertEqual(keys.focus, "a", "right wraps around siblings")
keys:handle("a"); keys:handle("l")
t.expect(keys.filter == "al" and keys:matches(keys:find("a")) and not keys:matches(keys:find("b")), "typing filters by label")
os.exit(t.summary() and 0 or 1)
