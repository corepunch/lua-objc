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

-- A stack can take only drags from other apps, such as the Finder: rows
-- dragged inside the app then pass it by.
local _, externalRefs = xml.render('<VStack id="zone" onDrop="drop" dropExternalOnly="true" />',
	{actions = {drop = function() return true end}}, ns)
t.expect(externalRefs.zone.dropExternalOnly, "dropExternalOnly reaches the native stack")
t.expect(not targetRefs.zone.dropExternalOnly, "stacks take drags from anywhere by default")
t.expect(ns._dropFiles(externalRefs.zone, {"/tmp/x"}), "files from the Finder still reach the handler")
t.expect(not ns._dropFiles(externalRefs.zone, {"/tmp/x"}, true), "files dragged inside the app pass it by")

-- A reorderable stack is still a file drop target: both features share the
-- stack's one set of dragging-destination methods.
local bothDropped
local _, bothRefs = xml.render([[<VStack id="zone" onDrop="drop" reorderable="true" reorderContainer="move">
  <Label text="A" /><Label text="B" />
</VStack>]], {actions = {drop = function(paths) bothDropped = paths; return true end, move = function() end}}, ns)
t.expect(ns._dropFiles(bothRefs.zone, {"/tmp/z"}), "a reorderable stack takes dropped files")
t.assertEqual(bothDropped and bothDropped[1], "/tmp/z", "the file reaches onDrop, not the reorder")
local types = {}
for _, type in ipairs(bothRefs.zone.registeredDraggedTypes) do types[tostring(type)] = true end
t.expect(types["public.file-url"] and types["org.luaobjc.reorder-item"], "the stack registers files and its items")

-- Folders and files opened with the app (Dock icon, Open With) wait for a
-- handler and then reach it.
ns._openFiles({"/tmp/early"})
local opened = {}
ns.onOpenFiles(function(paths) table.insert(opened, paths) end)
for _ = 1, 20 do if #opened > 0 then break end; ns._runLoopTick(0.01) end
t.expect(#opened == 1 and opened[1][1] == "/tmp/early", "an open that came before the handler is delivered once it is set")
ns._openFiles({"/tmp/a", "/tmp/b"})
t.expect(#opened == 2 and opened[2][1] == "/tmp/a" and opened[2][2] == "/tmp/b", "opened paths reach the handler in order")
ns.onOpenFiles(nil)

-- Quick Look records its items headlessly instead of opening the panel.
ns.quickLook({"/tmp/a", "/tmp/b"}, 2)
local looked = ns._quickLookItems()
t.expect(#looked == 2 and looked[1] == "/tmp/a" and looked[2] == "/tmp/b", "Quick Look keeps the items its arrow keys step through")
ns.quickLook({})
t.assertEqual(#ns._quickLookItems(), 0, "an empty list closes Quick Look")

-- Moving an item runs off the main thread and never replaces another.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/moveitem.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
os.execute("/bin/mkdir -p " .. root .. "/from " .. root .. "/to")
local function write(path) local file = assert(io.open(path, "w")); file:write("move me"); file:close() end
write(root .. "/from/a.txt"); write(root .. "/from/b.txt"); write(root .. "/to/b.txt")
local function move(path, folder)
	local result
	ns.moveItem(path, folder, function(ok, message, destination) result = {ok = ok, message = message, destination = destination} end)
	for _ = 1, 200 do if result then break end; ns._runLoopTick(0.01) end
	return result
end
local moved = move(root .. "/from/a.txt", root .. "/to")
t.expect(moved and moved.ok and moved.destination == root .. "/to/a.txt", "a file moves into the chosen folder")
t.expect(io.open(root .. "/to/a.txt") ~= nil and io.open(root .. "/from/a.txt") == nil, "the file is at its destination and gone from its source")
local clash = move(root .. "/from/b.txt", root .. "/to")
t.expect(clash and not clash.ok and clash.message:find("already exists", 1, true), "an item of the same name is never replaced")
t.expect(io.open(root .. "/from/b.txt") ~= nil, "a refused move leaves the item where it was")
os.execute("/bin/rm -rf " .. root)
os.exit(t.summary() and 0 or 1)
