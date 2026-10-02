_G.__headless = true
local t = require("TestKit")
local bridge = require("AppKitNative")
local native = require("StorageScan")
local Mock = require("apps.diskmap.services.Mock")
local Provider = require("apps.diskmap.services.Provider")
local Controller = require("apps.diskmap.Controller")
local FolderTree = require("apps.diskmap.helpers.FolderTree")

-- The native scanner lists a folder's tree: its largest children to
-- `treeDepth` levels, smaller items summed, deeper folders measured only.
local pipe = assert(io.popen("/usr/bin/mktemp -d /private/tmp/diskmap-folder.XXXXXXXX"))
local root = pipe:read("*l"); pipe:close()
local function write(path, bytes) local file = assert(io.open(path, "wb")); file:write(string.rep("x", bytes)); file:close() end
local MB = 1024 * 1024
os.execute("/bin/mkdir -p " .. root .. "/sub/inner")
write(root .. "/big.bin", 3 * MB)
write(root .. "/sub/half.bin", 2 * MB)
write(root .. "/sub/inner/deep.bin", 2 * MB)
for index = 1, 10 do write(root .. "/small" .. index .. ".txt", 1000) end
os.execute("/bin/ln '" .. root .. "/big.bin' '" .. root .. "/big link.bin'")
local result = native.scan({root}, {}, {treeDepth = 2, treeMinimumBytes = MB})
local folder = result.folders and result.folders[1]
t.expect(folder ~= nil and folder.directory == true, "a tree scan publishes the root folder")
local byName = {}
for _, child in ipairs(folder and folder.children or {}) do byName[child.name] = child end
local big = byName["big.bin"] or byName["big link.bin"]
t.expect(big and big.kb >= 3 * 1024 and not big.directory, "large files are listed with their size")
t.expect(not (byName["big.bin"] and byName["big link.bin"]), "a hard link counts once, under the first name met")
t.expect(byName.sub and byName.sub.directory and byName.sub.children ~= nil, "folders within the depth list their contents")
local inner
for _, child in ipairs(byName.sub and byName.sub.children or {}) do if child.name == "inner" then inner = child end end
t.expect(inner and inner.deeper and inner.children == nil and inner.kb >= 2 * 1024, "a folder below the depth is measured but not listed")
t.assertEqual(folder and folder.otherCount, 10, "files under the minimum are summed as smaller items")
t.expect(folder and folder.used and folder.used > 0, "a folder's last use is the latest use inside it")
t.expect(folder and folder.children[1].kb >= folder.children[#folder.children].kb, "children are listed largest first")
t.assertEqual(native.scan({root}, {}, {}).folders, nil, "scans without treeDepth publish no tree")
local logical = native.scan({root .. "/sub"}, {}, {treeDepth = 1, logicalRoots = {[root .. "/sub"] = "/Logical"}})
t.assertEqual(logical.folders[1].name, "Logical", "a logical root names the tree as people know it")
local job = native.start({root}, {}, {treeDepth = 1})
t.expect(type(native.progress(job)) == "number", "a running scan reports the items met so far")
native.cancel(job)
os.execute("/bin/rm -rf " .. root)

-- Saved snapshots list folders as entries with a few bytes of their own.
-- Such a folder opens as a folder, not as a file in its parent, and a
-- package entry met before its contents still takes them in.
local snapshot = Mock.new()
for _, item in ipairs({{"/Snap", 4096}, {"/Snap/Folder", 4096}, {"/Snap/Folder/a.bin", 5 * MB},
		{"/Snap/Tool.app", 4096}, {"/Snap/Tool.app/Contents/Tool", 3 * MB}}) do
	table.insert(snapshot.items, {path = item[1], allocatedBytes = item[2], countedBytes = item[2], used = 0})
end
local scanned
snapshot.scanFolder("/Snap/Folder", {treeDepth = 2}, function(folder) scanned = folder end)
t.expect(scanned and scanned.directory and scanned.children and scanned.children[1].name == "a.bin", "a snapshot's folder entry opens as a folder")
snapshot.scanFolder("/Snap/Folder/a.bin", {treeDepth = 2}, function(folder) scanned = folder end)
t.expect(scanned and not scanned.directory and scanned.children == nil, "a snapshot's file entry opens as a file")
snapshot.scanFolder("/Snap", {treeDepth = 3}, function(folder) scanned = folder end)
local tool
for _, child in ipairs(scanned and scanned.children or {}) do if child.name == "Tool.app" then tool = child end end
t.expect(tool and tool.directory and tool.kb >= 3 * 1024, "a package listed before its contents holds them")

-- The Folder Map page with the synthetic disk.
local service = Mock.new()
local home = service.home
local downloads = home .. "/Downloads"
local app = Controller.new(service)
app:createWindow()
local pc = app.pages.folder
local page = app:request("folder")
app:show("folder")
t.expect(pc.refs.folderEmpty ~= nil, "the page invites a drop until a folder is open")
t.assertEqual(Provider.folder({"--folder=/Volumes/Backup"}), "/Volumes/Backup", "--folder opens a folder at launch")

-- A folder dropped from the Finder anywhere on the window opens here.
app:show("overview")
t.expect(bridge._dropFiles(app.content, {downloads}), "a folder dropped on the window is taken")
t.assertEqual(app.destination, "folder", "a dropped folder shows the Folder Map")
t.assertEqual(page.path, downloads, "the dropped folder is measured")
local refs = pc.refs
t.expect(refs.folderSunburst ~= nil and refs.folderList.rowCount >= 3, "the folder shows as rings beside its contents")
t.assertEqual(bridge._tableCell(refs.folderList, 0, 0).textField.stringValue, "Old macOS Installer.dmg", "the largest item comes first")
local folderMeter = dofile("tests/fixtures/meter.lua")(bridge._tableCell(refs.folderList, 1, 0))
t.expect(folderMeter.value.stringValue ~= "" and folderMeter.share.stringValue:find("%%$") ~= nil, "the folder meter shows the size and its share")
t.expect(not folderMeter.bar.hidden, "the folder meter draws its bar")
t.expect(refs.folderSummary.text:find("~/Downloads", 1, true) ~= nil, "the summary names the folder from the home folder")
t.expect(app:badges().folder ~= nil, "the sidebar badge is the open folder's size")

-- Colorings and chart styles.
pc.actions.pickColoring(1)
t.assertEqual(page.coloring, "kinds", "the map colors by kind of file")
t.expect(pc.refs.folderLegend ~= nil, "kinds come with a legend")
pc.actions.pickColoring(2)
t.assertEqual(page.coloring, "age", "the map colors by last use")
local ages = {}
for _, row in ipairs(page.tree:legend(page.focus, "age")) do ages[row.name] = row end
t.expect(ages["1–3 years ago"] ~= nil, "an installer untouched for two years is in the older band")
pc.actions.pickColoring(0)
pc.actions.pickStyle(1)
t.expect(pc.refs.folderTreemap ~= nil and pc.refs.folderSunburst == nil, "Rectangles shows the folder as a treemap")
t.expect(pc.refs.folderList == nil, "Rectangles needs no list of folders")
pc.actions.pickStyle(0)
t.expect(pc.refs.folderList ~= nil, "Rings bring the list back")

-- Quick Look previews the selection with ⌘Y and steps through its folder.
local largest = downloads .. "/Old macOS Installer.dmg"
t.expect(not app.commandActions.canQuickLook(), "Quick Look needs a selection")
pc.actions.selectRow(nil, nil, page.tree:rows(page.focus, page.coloring)[1])
t.expect(app.commandActions.canQuickLook(), "a selected row can be previewed")
bridge._performMainMenuItem("File", "Quick Look")
t.expect(service.quickLooked and service.quickLooked.paths[service.quickLooked.index] == largest, "File › Quick Look previews the selected file")
t.expect(#service.quickLooked.paths >= 3, "the arrow keys step through the rest of the folder")

-- Row menus: Quick Look, Finder, Move to…, Trash, Mark and Copy.
local function titles(list, row)
	local names = {}
	for _, item in ipairs(bridge._tableRowMenu(list, row)) do if item.title then names[item.title] = true end end
	return names
end
local function perform(list, row, title)
	for index, item in ipairs(bridge._tableRowMenu(list, row)) do
		if item.title == title then bridge._tableRowMenu(list, row, index); return true end
	end
	return false
end
local menu = titles(pc.refs.folderList, 1)
for _, title in ipairs({"Quick Look", "Show in Finder", "Move to…", "Move to Trash…", "Mark for Cleanup", "Copy Path"}) do
	t.expect(menu[title], "a file's menu offers " .. title)
end

-- Move to… offloads it to another folder; the map follows at once.
local before = page.tree.root.bytes
service.pickFolder = function() return home .. "/Archive" end
t.expect(perform(pc.refs.folderList, 1, "Move to…"), "Move to… is performed from the row menu")
t.expect(page.tree:find(largest) == nil and page.tree.root.bytes < before, "the moved file leaves the map without a new scan")
t.expect((service.fileCounts[home .. "/Archive/Old macOS Installer.dmg"] or 0) > 0, "the file is in its new folder")
t.expect(table.concat(service.operationLog(), "\n"):find("Move", 1, true) ~= nil, "the move is recorded in the history")
t.expect(bridge._tableCell(pc.refs.folderList, 0, 0).textField.stringValue ~= "Old macOS Installer.dmg", "the list follows the move")

-- Move to Trash asks first, then removes the row.
local first = page.tree:rows(page.focus, page.coloring)[1]
service.confirmTrashPath = function() return true end
t.expect(perform(pc.refs.folderList, 1, "Move to Trash…"), "Move to Trash… is performed from the row menu")
t.expect(page.tree:find(first.path) == nil, "the trashed item leaves the map")
t.expect((service.fileCounts[home .. "/.Trash/" .. first.name] or 0) > 0, "it is in the Trash")
local remaining
for _, row in ipairs(page.tree:rows(page.focus, page.coloring)) do if not row.directory and not row.other then remaining = row; break end end

-- System locations and standard folders are never moved.
t.expect(not FolderTree.validateChange(downloads), "a standard folder is never moved")
t.expect(not FolderTree.validateChange("/Applications/Safari.app"), "items outside the home folder and other disks are not moved")
t.expect(FolderTree.validateChange("/Volumes/Backup/Old"), "items on another disk may be moved")
t.expect(not FolderTree.validateChange("/Volumes/Backup"), "a disk itself is never moved")
t.expect(not FolderTree.validateDestination(largest, downloads), "a move needs a different folder")
t.expect(not FolderTree.validateDestination(downloads .. "/a", downloads .. "/a/b"), "a folder is never moved into itself")

-- Looking inside folders, back up, and scanning a folder below the depth.
local options = FolderTree.scanOptions
FolderTree.scanOptions = {treeDepth = 1, treeMinimumBytes = options.treeMinimumBytes}
app:openFolder(home)
t.expect(page.tree:needsScan(home .. "/Library"), "a folder below the first scan's depth is measured when opened")
pc.actions.setFocus(home .. "/Library")
t.assertEqual(page.focus, home .. "/Library", "opening it shows its contents")
t.expect(#page.tree:find(home .. "/Library").children > 0, "its contents join the tree")
t.assertEqual(#page.tree:trail(page.focus), 2, "the breadcrumb leads back to the folder")
pc.actions.up()
t.assertEqual(page.focus, home, "the center goes back up")
FolderTree.scanOptions = options

-- A dropped file opens its folder with the file selected.
app:openFolder(remaining.path)
t.expect(page.path == downloads and page.selected == remaining.path, "a file opens its folder with it selected")

-- A folder dropped on the Dock icon opens like one dropped on the window.
app:show("overview")
service.openHandler({home .. "/Documents"})
t.expect(app.destination == "folder" and page.path == home .. "/Documents", "a folder opened with Diskmap is shown")

-- File › Open Folder… measures the chosen folder.
service.pickFolder = function() return home .. "/Library" end
bridge._performMainMenuItem("File", "Open Folder…")
t.assertEqual(page.path, home .. "/Library", "Open Folder… opens the chosen folder")

-- A folder that cannot be read explains itself.
app:openFolder("/Nowhere")
t.expect(pc.refs.folderFailed ~= nil, "a folder that cannot be measured says so")

-- Large Files rows offer Quick Look and Move to… as well.
local Files = require("apps.diskmap.models.Files")
local dmg
for _, row in ipairs(Files:rows("All")) do if row.name == "Old macOS Installer.dmg" then dmg = row end end
local fileMenu = {}
for _, item in ipairs(dmg and app.actions:file(dmg) or {}) do if item.title then fileMenu[item.title] = true end end
t.expect(fileMenu["Quick Look"] and fileMenu["Move to…"], "large files can be previewed and offloaded")

os.exit(t.summary() and 0 or 1)
