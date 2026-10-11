_G.__headless = true
local t = require("TestKit")
local Harness = require("tests.support.diskmap")
local FolderTree = require("apps.diskmap.helpers.FolderTree")

-- The Folder Map: any folder as a list, largest first, with what Diskmap
-- knows about each item, looking inside and coming back up.
local host = Harness.env()
local home = host.env.model.home
local page = Harness.mount("folder", host, {path = home .. "/Developer"})
local rows = host.lists.folderList
t.expect(#rows >= 7, "the folder's children are listed")
t.expect(rows[1].bytes >= rows[2].bytes, "largest first")
t.assertEqual(rows[1].name, "rustle", "the biggest project leads")
t.expect(rows[1].subtitle:find("items", 1, true) and rows[1].subtitle:find("written", 1, true), "a row says how many items and when it was written")
t.assertEqual(host.presented.hidden.up, true, "Up is hidden at the measured folder")
t.expect(host.presented.subtitle:find("~/Developer", 1, true), "the subtitle names the folder from home")
t.expect(rows[1].removable == true and rows[1].removeHelp == "Move to Trash…", "a folder in the home folder can be removed")

-- An item another page measured reads as that item.
local experiment
for _, row in ipairs(rows) do if row.name == "rustle-experiment" then experiment = row end end
t.expect(experiment and experiment.subtitle:find("Git · Your decision", 1, true), "a worktree reads as the Worktrees page describes it")

-- Looking inside, then up; the location follows, so Back can return.
page.actions.drillRow(nil, nil, {id = home .. "/Developer/rustle"})
t.assertEqual(host.presented.title, "rustle", "looking inside titles the window by the folder")
t.assertEqual(page:location().focus, home .. "/Developer/rustle", "the location names the focus")
local inside = host.lists.folderList
t.assertEqual(inside[1].name, "target", "the folder's contents are listed")
t.expect(inside[1].subtitle:find("Cargo · Your decision", 1, true), "a measured build folder reads as what it is")
t.assertEqual(host.presented.hidden.up, false, "Up is offered inside")
page.actions.up()
t.assertEqual(host.presented.title, "Developer", "Up returns to the folder")

-- A macOS folder is explained from the knowledge of macOS; standard folders cannot be removed.
Harness.mount("folder", host, {path = home .. "/Library"})
local caches
for _, row in ipairs(host.lists.folderList) do if row.name == "Caches" then caches = row end end
t.expect(caches and caches.subtitle:find("rebuilt when needed", 1, true), "~/Library/Caches reads as what it is")
t.expect(caches.removable == false, "and cannot be removed from the map")
local menu = page.actions.rowMenu(nil, nil, caches)
t.assertEqual(menu[1].title, "Look Inside", "a folder's menu looks inside")
local titles = {}
for _, item in ipairs(menu) do if item.title then table.insert(titles, item.title) end end
t.assertEqual(table.concat(titles, ", "), "Look Inside, Show in Finder, Copy Path", "and offers no removal for a standard folder")

-- The tree: removal updates ancestors without measuring again.
local tree
host.service.scanFolder(home .. "/Developer", FolderTree.scanOptions, function(folder) tree = FolderTree.new(home .. "/Developer", folder) end)
local before = tree.root.bytes
local removed = tree:remove(home .. "/Developer/rustle/target")
t.expect(removed > 0 and tree.root.bytes == before - removed, "removing a node shrinks its ancestors")
t.assertEqual(tree:find(home .. "/Developer/rustle/target"), nil, "and unindexes it")
t.expect(FolderTree.validateChange(home .. "/Developer/x", home), "home items may change")
t.expect(not FolderTree.validateChange("/Library/x", home), "shared items may not")
t.expect(not FolderTree.validateChange(home .. "/Pictures/Photos Library.photoslibrary/x", home), "nothing inside a package may")

-- A missing folder fails honestly.
Harness.mount("folder", host, {path = home .. "/nowhere"})
t.assertEqual(host.presented.phase, "failed", "a folder that cannot be read says so")

os.exit(t.summary() and 0 or 1)
