_G.__headless = true
local t = require("TestKit")
local bridge = require("AppKitNative")
local Harness = require("tests.support.diskmap")

-- Every page of the manifest draws from the synthetic Mac, with the lists
-- its route names filled, and the window titled by the page.
local host = Harness.env()
local manifest = host.env.manifest
for _, entry in ipairs(manifest.order) do
	local params = entry.id == "folder" and {path = host.env.model.home .. "/Developer"} or {}
	local page = Harness.mount(entry.id, host, params)
	t.expect(page.refs ~= nil, entry.id .. " renders")
	t.expect(type(host.presented.title) == "string" and host.presented.title ~= "", entry.id .. " titles the window")
end

-- A source page: sections with rows, the remove column, the row menu.
local page = Harness.mount("xcode", host)
t.expect(page.refs.list_derived.rowCount == 4 and page.refs.list_support.rowCount == 4, "Xcode lists DerivedData and device support")
t.expect(page.refs.section_backups ~= nil, "device backups are a section")
t.assertEqual(host.presented.hidden.addFolder, true, "only project pages add folders")
local tidepool = host.env.model.home .. "/Library/Developer/Xcode/DerivedData/Tidepool-abcdefghijklmnopqrstuvwxyzabcd"
local menu = page.actions.rowMenu(nil, nil, {id = tidepool})
local titles = {}
for _, item in ipairs(menu) do if item.title then table.insert(titles, item.title) end end
t.assertEqual(table.concat(titles, ", "), "Look Inside, Show in Finder, Move to Trash…, Keep, Copy Path", "a row's menu offers the same verbs everywhere")
t.expect(host.presented.subtitle:find("safe to remove", 1, true), "the subtitle says what is safe")
local rows = host.lists.list_support
t.expect(rows[1].removable == false and rows[1].removeHelp:find("Keep", 1, true), "the kept version cannot be removed and says why")
t.expect(rows[2].removable == true and rows[2].removeHelp == "Move to Trash…", "an older version can be")
local tools = host.lists.list_tools
t.expect(tools[1].removable == false and tools[1].removeHelp:find("administrator", 1, true), "a root-owned folder says Finder needs an administrator")

-- Projects: Add Folder is offered; a system row cannot be removed.
Harness.mount("projects", host)
t.assertEqual(host.presented.hidden.addFolder, false, "Projects can add a folder")
Harness.mount("system", host)
local volumes = host.lists.list_volumes
t.expect(volumes[1].removable == false and volumes[1].status == "Managed by macOS", "a volume cannot be removed and says why")
t.expect(volumes[1].hasMenu == false, "a volume without row actions does not offer More")
t.assertEqual(#host.env:page("system"):flow("Rows"):menu(require("apps.diskmap.models.Items"):find("volume:Preboot")), 0, "a volume has no path and no menu")
local menuSystem = host.env:page("system"):flow("Rows"):menu(require("apps.diskmap.models.Items"):byPath("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_LinguisticData"))
local systemTitles = {}
for _, item in ipairs(menuSystem) do if item.title then table.insert(systemTitles, item.title) end end
t.assertEqual(table.concat(systemTitles, ", "), "Look Inside, Show in Finder, Copy Path", "a system folder's menu offers no removal and no Keep")
t.assertEqual(#menuSystem, 4, "with one separator")
t.expect(host.lists.list_assets[1].hasMenu == true, "a system asset with a path offers More")

-- The Overview opens a source; Remove Everything Safe is offered only when something is safe.
local overview = Harness.mount("overview", host)
t.assertEqual(overview.refs.categories.rowCount, 8, "the Overview lists the eight sources")
overview.actions.open(nil, nil, {id = "simulators"})
t.assertEqual(host.events[#host.events].args[1], "simulators", "a source row opens its page")
t.assertEqual(host.presented.hidden.removeSafe, false, "Remove Everything Safe is offered")
t.assertEqual(host.presented.hidden.notice, true, "no notice before a removal")

-- Alignment (AGENTS.md): in every list the symbols share one column and the
-- names one edge, whatever the symbol.
local app = Harness.app()
app:show("system")
bridge._flushLayout()
local volumeList = app.page.refs.list_volumes
local assetList = app.page.refs.list_assets
t.expect(bridge._tableCell(volumeList, 5, 0).actionButton.hidden, "More is absent where the row has no menu")
t.expect(not bridge._tableCell(assetList, 5, 0).actionButton.hidden, "More is visible where row actions exist")
t.expect(not bridge._tableCell(volumeList, 4, 0).actionButton.enabled, "macOS volume removal stays disabled")
t.assertEqual(bridge._tableRowMenu(assetList, 1)[1].title, "Look Inside", "the visible More button has a native row menu")
app:show("simulators")
bridge._flushLayout()
local list = app.page.refs.list_devices
local centers, texts = {}, {}
for index = 0, list.rowCount - 1 do
	local cell = bridge._tableCell(list, 0, index)
	table.insert(centers, cell.imageView.frame.origin.x + cell.imageView.frame.size.width / 2)
	table.insert(texts, cell.textField.frame.origin.x)
end
t.expect(#centers >= 4, "device rows were drawn")
for index = 2, #centers do
	t.expect(math.abs(centers[index] - centers[1]) < 0.01, "device symbol " .. index .. " is centered on one line")
	t.expect(math.abs(texts[index] - texts[1]) < 0.01, "device name " .. index .. " starts at one edge")
end
t.expect(app.window ~= nil and app.navigation:index("simulators") ~= nil, "the window shows the page in the sidebar")
app:show("folder", {path = host.env.model.home .. "/Developer"})
t.expect(app.page.refs.folderList.rowCount > 0, "the Folder Map lists the folder")
app.navigation:back()
t.assertEqual(app.destination, "simulators", "Back returns to the previous page")
t.expect(app:badges().xcode ~= nil, "the sidebar shows each source's total")
app:dispose()

os.exit(t.summary() and 0 or 1)
