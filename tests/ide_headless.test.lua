_G.__headless = true

local App = require("App")
local ns = require("AppKit")
local Source = require("examples.IDEKit.Workspace")
require("examples.IDEKit.plugins.ImageViewer")
local Recent = require("examples.IDEKit.state.Recent")
local t = require("TestKit")

local files = {
	"examples/IDEKit/init.lua",
	"examples/IDEKit/App.lua",
	"examples/IDEKit/state/Recent.lua",
	"examples/IDEKit/Recent.lua",
	"examples/IDEKit/Welcome.lua",
	"examples/IDEKit/Workspace.lua",
	"examples/IDEKit/plugins/TextEditor.lua",
	"examples/IDEKit/plugins/ImageViewer.lua",
	"examples/IDEKit/plugins/NativeControls.lua",
}

for _, path in ipairs(files) do
	local ok, err = pcall(function()
		local fn, loadErr = loadfile(path)
		if not fn then error(loadErr) end
		return fn()
	end)
	t.expect(ok, path .. " loads headlessly")
	if not ok then
		io.stderr:write("  " .. tostring(err) .. "\n")
	end
end

local tempRoot = "/private/tmp/lua-objc-ide-headless"
local recent = Recent.new {
	key = "headless-route-test",
	storageRoot = tempRoot,
	limit = 4,
}
recent:clear()

t.expect(App.resolvePluginByFile("sample.svg", "editor") ~= nil,
	"IDE plugin host resolves the image editor")

local calls = {}
local app = App.new {
	recent = recent,
	openFolder = function(self, folder)
		calls[#calls + 1] = { kind = "folder", path = folder }
		return { kind = "folder", path = folder }
	end,
	openFile = function(self, path)
		calls[#calls + 1] = { kind = "file", path = path }
		return { kind = "file", path = path }
	end,
	welcome = function(self)
		calls[#calls + 1] = { kind = "welcome" }
		return { kind = "welcome" }
	end,
}

local originalArg = _G.arg

_G.arg = {}
local welcomeView = app:run()
t.assertEqual(welcomeView.kind, "welcome", "App:run shows welcome without a folder argument")
t.assertEqual(calls[#calls].kind, "welcome", "welcome callback is used when no folder is passed")

_G.arg = { "/private/tmp/project-a" }
local workspaceView = app:run()
t.assertEqual(workspaceView.kind, "folder", "App:run opens a folder when one is passed")
t.assertEqual(calls[#calls].path, "/private/tmp/project-a", "folder argument is forwarded to openFolder")

_G.arg = originalArg

app:openFolder("/private/tmp/project-b")
app:openFile("/private/tmp/project-b/main.lua")

local imageWindow = Source.openFile("tests/fixtures/oversized.svg", app)
t.expect(imageWindow ~= nil, "image source route creates a window")
t.assertEqual(imageWindow.title, "oversized.svg", "image source route uses the file name as title")

t.assertEqual(#recent:folders(), 2, "recent folders are stored separately")
t.assertEqual(#recent:files(), 2, "recent files are stored separately")
t.assertEqual(recent:folders()[1].path, "/private/tmp/project-b", "most recent folder is first")
t.assertEqual(recent:files()[1].path, "tests/fixtures/oversized.svg", "most recent file is first")
t.assertEqual(recent:files()[2].path, "/private/tmp/project-b/main.lua", "older file remains available")

local sourceWindow, sourceSession = Source.open(
	"examples/IDEKit/",
	nil,
	"examples/IDEKit/init.lua")
t.expect(sourceWindow ~= nil, "source workspace creates a document window")
t.assertEqual(sourceWindow.title, "init.lua",
	"source document uses its filename as the native window-tab title")
t.assertEqual(sourceWindow.tabbingIdentifier, "lua-objc.ide:examples/IDEKit/",
	"source documents opt into one AppKit window tab group")
local sourceWorkspaceState = sourceWindow:workspaceState()
t.expect(sourceWorkspaceState.nativeSidebar,
	"source workspace uses AppKit's semantic floating sidebar")
t.assertEqual(sourceWorkspaceState.itemCount, 3,
	"source editor and preview use sibling native split items")
t.expect(sourceWorkspaceState.tracksContentDivider,
	"editor divider continues through the native toolbar")
t.expect(sourceWorkspaceState.hasSidebarToggle,
	"source workspace has AppKit's standard sidebar toggle")
t.expect(sourceWorkspaceState.tracksSidebarDivider,
	"sidebar toggle follows the native sidebar divider")
t.assertEqual(sourceWorkspaceState.topAccessoryCount, 0,
	"source document does not insert a custom tab control")
local sidebarItem = ns.ToolbarItem(sourceWindow, "toggleSidebar")
t.expect(sidebarItem ~= nil,
	"standard sidebar toolbar item is addressable by its Lua alias")
local buildItem = ns.ToolbarItem(sourceWindow, "build")
local runItem = ns.ToolbarItem(sourceWindow, "run")
t.assertEqual(buildItem.label, "Build",
	"source workspace exposes the decorative Build toolbar item")
t.assertEqual(runItem.label, "Run",
	"source workspace exposes the decorative Run toolbar item")

local initialTabCount = ns.windowTabCount(sourceWindow)
local initialPrimaryPath = sourceSession.documents[1].path
local otherFile = initialPrimaryPath:match("(.+/)")
	and initialPrimaryPath:gsub("init%.lua", "App.lua")
	or "examples/IDEKit/App.lua"
sourceSession.openPath(otherFile, false)
t.expect(sourceSession.documents[1].path ~= initialPrimaryPath,
	"openPath replaces the primary editor document without creating a tab")
t.assertEqual(sourceSession.documents[1].path, otherFile,
	"primary editor now shows the opened file")
t.assertEqual(ns.windowTabCount(sourceWindow), initialTabCount,
	"single file selection does not create a window tab")

local primaryPath = sourceSession.documents[1].path
local tabPath = primaryPath == "examples/IDEKit/plugins/TextEditor.lua"
	and "examples/IDEKit/Workspace.lua"
	or "examples/IDEKit/plugins/TextEditor.lua"
sourceSession.openPath(tabPath, true)
local commandTabCount = ns.windowTabCount(sourceWindow)
t.expect(commandTabCount > initialTabCount,
	"Command-click routing opens a separate native window tab")
t.assertEqual(sourceSession.documents[#sourceSession.documents].path, tabPath,
	"the new native tab contains the Command-clicked document")
t.assertEqual(
	ns.windowTabCount(sourceSession.documents[#sourceSession.documents].window),
	commandTabCount,
	"the Command-clicked document joins the primary AppKit tab group")

recent:clear()

os.exit(t.summary() and 0 or 1)
