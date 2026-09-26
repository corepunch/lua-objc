local t = require("TestKit")
local ns = require("AppKit")
local bridge = require("AppKitNative")
local xml = require("ui.xml")
local commands = require("ui.commands")

local function menu(snapshot, title)
	for _, entry in ipairs(snapshot.menus) do
		if entry.title == title then return entry end
	end
end

local function item(items, title)
	for _, entry in ipairs(items or {}) do
		if entry.title == title then return entry end
	end
end

local function titles(items)
	local out = {}
	for _, entry in ipairs(items) do table.insert(out, entry.separator and "-" or entry.title) end
	return table.concat(out, "|")
end

-- App names come from the declaration, else the entry folder or file.
t.assertEqual(commands.appName("Diskmap"), "Diskmap", "declared app name wins")
t.assertEqual(commands.appName(nil, "apps/diskmap/init.lua"), "Diskmap", "entry folder names the app")
t.assertEqual(commands.appName(nil, "apps/adventure-arena/init.lua"), "Adventure Arena", "hyphenated folders are title-cased")
t.assertEqual(commands.appName(nil, "demo/hello.lua"), "Hello", "a flat script names the app")

-- Standard layout, SwiftUI group placement and separator collapsing.
local built = commands.build({appName = "Sample"})
local order = {}
for _, entry in ipairs(built.menus) do table.insert(order, entry.title) end
t.assertEqual(table.concat(order, ","), "Sample,File,Edit,View,Window,Help", "standard menus in HIG order")
t.assertEqual(titles(built.menus[1].items),
	"About Sample|-|Services|-|Hide Sample|Hide Others|Show All|-|Quit Sample", "app menu has classic entries")

local custom = commands.build({appName = "Sample",
	groups = {
		{placement = "appSettings", position = "replacing", items = {{title = "Settings…", keyEquivalent = ",", action = function() end}}},
		{placement = "sidebar", position = "after", items = {{title = "Reload", action = function() end}}},
		{placement = "undoRedo", position = "replacing", items = {}},
		{placement = "pasteboard", position = "replacing", items = {}},
		{placement = "textEditing", position = "replacing", items = {}},
	},
	menus = {{title = "Tools", items = {{title = "Run", action = function() end}}}},
})
order = {}
for _, entry in ipairs(custom.menus) do table.insert(order, entry.title) end
t.assertEqual(table.concat(order, ","), "Sample,File,View,Tools,Window,Help",
	"CommandMenu sits before Window and an emptied Edit menu disappears")
t.assertEqual(titles(custom.menus[1].items),
	"About Sample|-|Settings…|-|Services|-|Hide Sample|Hide Others|Show All|-|Quit Sample", "appSettings replaced")
t.assertEqual(titles(custom.menus[3].items),
	"Show Toolbar|Customize Toolbar…|-|Show Sidebar|-|Reload|-|Enter Full Screen", "after=sidebar follows the sidebar group")
t.expect(not pcall(commands.build, {groups = {{placement = "nope", items = {}}}}), "unknown placement is rejected")

-- XML: <Commands> on a <Window> installs the native menu bar.
local ran, validated = {}, {enabled = false, checked = true}
local cfg = xml.render([[
<Window title="Menus" width="400" height="300">
  <Commands appName="Menu Test">
    <CommandGroup replacing="appSettings">
      <MenuItem title="Settings…" keyEquivalent="," action="settings" />
    </CommandGroup>
    <CommandMenu title="Tools">
      <MenuItem title="Run" keyEquivalent="r" modifiers="command,shift" action="run" />
      <MenuItem title="Stop" keyEquivalent="." action="stop" validate="canStop" />
      <Separator />
      <MenuItem title="Mode">
        <MenuItem title="Fast" action="fast" checked="true" />
        <MenuItem title="Careful" action="careful" disabled="true" />
      </MenuItem>
    </CommandMenu>
    <HelpTopic title="Getting Started" keywords="first scan begin" action="helpStart" />
    <HelpTopic title="Free Up Space" keywords="clean trash" action="helpClean" />
  </Commands>
</Window>]], {actions = {
	settings = function() table.insert(ran, "settings") end,
	run = function() table.insert(ran, "run") end,
	stop = function() table.insert(ran, "stop") end,
	canStop = function() return validated.enabled, validated.checked end,
	fast = function() table.insert(ran, "fast") end,
	careful = function() table.insert(ran, "careful") end,
	helpStart = function() table.insert(ran, "help:start") end,
	helpClean = function() table.insert(ran, "help:clean") end,
}}, ns)
t.expect(cfg.commands and cfg.commands.__commands, "Window collects <Commands>")
t.assertEqual(#cfg.commands.helpTopics, 2, "help topics are collected")
local window = ns.Window(cfg)
t.expect(window ~= nil, "window with commands is created")

local snapshot = bridge._mainMenuSnapshot()
t.assertEqual(snapshot.appName, "Menu Test", "process carries the app name")
t.assertEqual(snapshot.menus[1].title, "Menu Test", "app menu is titled with the app name")
t.expect(item(snapshot.menus[1].items, "About Menu Test") ~= nil, "About names the app")
t.expect(item(snapshot.menus[1].items, "Quit Menu Test").keyEquivalent == "q", "Quit names the app and keeps ⌘Q")
t.expect(item(snapshot.menus[1].items, "Hide Others").modifiers == "command,option", "Hide Others uses ⌥⌘H")
t.expect(snapshot.servicesMenu, "Services submenu is registered with NSApp")
t.assertEqual(snapshot.windowsMenu, "Window", "Window menu is NSApp.windowsMenu")
t.assertEqual(snapshot.helpMenu, "Help", "Help menu is NSApp.helpMenu")
t.expect(item(menu(snapshot, "Help").items, "Menu Test Help") ~= nil, "Help item names the app")
t.expect(item(menu(snapshot, "View").items, "Show Sidebar").selector == "toggleSidebar:", "View has the standard sidebar command")
t.expect(item(menu(snapshot, "Edit").items, "Find") ~= nil, "Edit has a Find submenu")

local tools = menu(snapshot, "Tools")
t.expect(tools ~= nil, "CommandMenu is installed")
t.assertEqual(item(tools.items, "Run").modifiers, "command,shift", "modifiers are applied")
t.expect(item(tools.items, "Run").enabled, "action items are enabled")
local stop = item(tools.items, "Stop")
t.expect(not stop.enabled and stop.checked, "validate returns enabled, checked")
t.expect(tools.items[3].separator, "Separator becomes a native separator")
local mode = item(tools.items, "Mode")
t.expect(item(mode.items, "Fast").checked, "static checked state")
t.expect(not item(mode.items, "Careful").enabled, "static disabled item stays disabled under autoenabling")

bridge._performMainMenuItem("Tools", "Run")
bridge._performMainMenuItem("Menu Test", "Settings…")
bridge._performMainMenuItem("Tools", "Mode", "Fast")
t.expect(not pcall(bridge._performMainMenuItem, "Tools", "Stop"), "a disabled item cannot be performed")
validated.enabled = true
bridge._performMainMenuItem("Tools", "Stop")
t.assertEqual(table.concat(ran, ","), "run,settings,fast,stop", "menu actions run in order")

-- Help menu search matches every term across title and keywords.
t.assertEqual(table.concat(bridge._searchHelp("scan"), ","), "Getting Started", "keywords match")
t.assertEqual(table.concat(bridge._searchHelp("free trash"), ","), "Free Up Space", "all terms must match")
t.assertEqual(#bridge._searchHelp("nothing here"), 0, "no match yields no results")
bridge._searchHelp("clean", 1)
t.assertEqual(ran[#ran], "help:clean", "choosing a result performs its action")

-- A later window without commands leaves the menu bar alone.
ns.Window({title = "Second", width = 200, height = 100})
t.expect(menu(bridge._mainMenuSnapshot(), "Tools") ~= nil, "plain windows keep the installed commands")

os.exit(t.summary() and 0 or 1)
