_G.__headless = true
local t = require("TestKit")
local bridge = require("AppKitNative")
local Mock = require("apps.diskmap.services.Mock")
local Controller = require("apps.diskmap.Controller")
local Help = require("apps.diskmap.helpers.Help")
local Navigation = require("apps.diskmap.controllers.NavigationController")

local function find(items, title)
	for _, entry in ipairs(items or {}) do if entry.title == title then return entry end end
end
local function menu(title)
	return find(bridge._mainMenuSnapshot().menus, title)
end

local service = Mock.new()
local calls = {}
service.openSettings = function(section) table.insert(calls, "settings:" .. tostring(section)) end
service.openDiskUtility = function() table.insert(calls, "diskUtility") end
local app = Controller.new(service)
app:createWindow()

-- The menu bar is named for Diskmap and keeps the classic macOS entries.
local snapshot = bridge._mainMenuSnapshot()
t.assertEqual(snapshot.appName, "Diskmap", "the process is named Diskmap")
local order = {}
for _, entry in ipairs(snapshot.menus) do table.insert(order, entry.title) end
t.assertEqual(table.concat(order, ","), "Diskmap,File,Edit,View,Go,Storage,Window,Help",
	"menus follow the HIG order with Go and Storage before Window")
local appMenu = snapshot.menus[1].items
for _, title in ipairs({"About Diskmap", "Settings…", "Services", "Hide Diskmap", "Hide Others", "Show All", "Quit Diskmap"}) do
	t.expect(find(appMenu, title) ~= nil, "app menu has " .. title)
end
t.assertEqual(find(appMenu, "Settings…").keyEquivalent, ",", "Settings uses ⌘,")
t.expect(find(menu("File").items, "Close") ~= nil, "File keeps Close")
t.expect(find(menu("Edit").items, "Copy") ~= nil, "Edit keeps the pasteboard commands")
t.assertEqual(find(find(menu("Edit").items, "Find").items, "Find…").keyEquivalent, "f", "Find… uses ⌘F")
t.expect(find(menu("View").items, "Show Sidebar") ~= nil, "View toggles the sidebar")
t.expect(find(menu("Window").items, "Minimize") ~= nil, "Window has Minimize")
t.assertEqual(snapshot.windowsMenu, "Window", "Window menu lists windows")
t.assertEqual(snapshot.helpMenu, "Help", "Help menu hosts the search field")

-- Go lists every sidebar page, checks the current one and numbers the first nine.
local go = menu("Go").items
local pages = 0
for _, page in ipairs(Navigation.destinations) do
	if page.id then
		pages = pages + 1
		local entry = find(go, page.name)
		t.expect(entry ~= nil, "Go lists " .. page.name)
		t.assertEqual(entry.keyEquivalent, page.key or "", page.name .. " shortcut")
	end
end
t.assertEqual(pages, 25, "every destination, including the Folder Map, each kind of work, macOS Folders and Diskmap Help")
t.expect(find(go, "Overview").checked and not find(go, "Large Files").checked, "the current page is checked")
bridge._performMainMenuItem("Go", "Large Files")
t.assertEqual(app.destination, "files", "Go › Large Files opens the page")
t.expect(find(menu("Go").items, "Large Files").checked, "the checkmark follows navigation")

-- Storage commands validate against the scan and the Trash.
local storage = menu("Storage").items
t.assertEqual(find(storage, "Refresh").enabled, app.env.scan.job == nil, "Refresh is available only between scans")
t.assertEqual(find(storage, "Stop Measuring").enabled, app.env.scan.job ~= nil, "Stop is available only while scanning")
t.assertEqual(find(storage, "Empty Trash…").modifiers, "command,shift", "Empty Trash uses ⇧⌘⌫")
t.assertEqual(find(storage, "Empty Trash…").enabled, app.commands:canEmptyTrash(), "Empty Trash validates the Trash")
bridge._performMainMenuItem("Storage", "Full Disk Access Settings…")
bridge._performMainMenuItem("Storage", "Storage Settings…")
bridge._performMainMenuItem("Storage", "Open Disk Utility")
t.assertEqual(table.concat(calls, ","), "settings:privacy,settings:nil,diskUtility", "Storage opens system settings and Disk Utility")

-- Help opens Diskmap Help; its search finds help and guide topics.
t.assertEqual(find(menu("Help").items, "Diskmap Help").keyEquivalent, "?", "Diskmap Help uses ⌘?")
bridge._performMainMenuItem("Help", "Diskmap Help")
t.assertEqual(app.destination, "help", "Help › Diskmap Help opens the help page")
t.expect(app.page.refs.help_welcome ~= nil and app.page.refs.help_trash ~= nil, "help lists its topics")
t.expect(app.page.refs.link_files ~= nil, "a topic links to its page")

local results = bridge._searchHelp("leftovers")
t.expect(#results >= 1 and results[1] == "Find data left by deleted apps", "help search finds a task by keyword")
t.expect(#bridge._searchHelp("preboot") >= 1, "help search includes Storage Guide topics")
bridge._searchHelp("leftovers", 1)
t.assertEqual(app.destination, "help", "a help result opens Diskmap Help")
t.assertEqual(app.query, "Find data left by deleted apps", "the result filters help to its topic")
t.assertEqual(app.searchField.stringValue, app.query, "the toolbar search shows the filter")
t.expect(app.page.refs.help_leftovers ~= nil and app.page.refs.help_trash == nil, "only the chosen topic remains")

-- The shortcut topic is generated from the installed menu bar.
bridge._performMainMenuItem("Help", "Keyboard Shortcuts")
t.expect(app.page.refs.help_shortcuts ~= nil, "Keyboard Shortcuts opens its help topic")
local listed = table.concat((function()
	local lines = {}
	for _, entry in ipairs(app.shortcuts) do table.insert(lines, Help.shortcut(entry.key, entry.modifiers) .. " " .. entry.title) end
	return lines
end)(), "\n")
t.expect(listed:find("⌘R Storage › Refresh", 1, true) ~= nil, "shortcuts include Refresh")
t.expect(listed:find("⇧⌘⌫ Storage › Empty Trash…", 1, true) ~= nil, "shortcuts name the delete key")
t.expect(listed:find("⌘1 Go › Overview", 1, true) ~= nil, "shortcuts include pages")
t.expect(listed:find("⌘Q Diskmap › Quit Diskmap", 1, true) ~= nil, "shortcuts include standard commands")
t.assertEqual(Help.shortcut("f", "command,control"), "⌃⌘F", "modifier symbols follow macOS order")

-- Every help topic that opens something resolves to a page or command.
local links = require("apps.diskmap.controllers.CommandsController").links()
for _, chapter in ipairs(Help.chapters) do
	for _, topic in ipairs(chapter.topics) do
		local target = topic.show or topic.command
		if target then
			t.expect(links[target] ~= nil, topic.id .. " links to a known target")
			t.expect(app.env.manifest.pages[target] ~= nil or app.commandActions[target] ~= nil, topic.id .. " target is actionable")
		end
	end
end

-- Find focuses the toolbar search field.
app:search("overview", "")
t.expect(pcall(bridge._performMainMenuItem, "Edit", "Find", "Find…"), "Edit › Find › Find… reaches the search field")

os.exit(t.summary() and 0 or 1)
