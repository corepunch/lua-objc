local ns = require("AppKit")
local t = require("TestKit")
local App = require("App")
local PluginKit = require("PluginKit")
local ImageViewerPlugin = require("Plugins.ImageViewer")
local TextEditorPlugin = require("Plugins.TextEditor")
local RecentState = require("examples.ide.state.recent")

-- VStack: can create and add children without crashing

local ok = pcall(function()
	local v = ns.VStack {
		ns.Text "First",
		ns.Text "Second",
	}
end)
t.expect(ok, "VStack creates without error")

-- HStack: can create with Spacer

ok = pcall(function()
	local h = ns.HStack {
		ns.Text "Left",
		ns.Spacer(),
		ns.Text "Right",
	}
end)
t.expect(ok, "HStack creates without error")

-- Window with visible=false does not show

local win = ns.Window {
	title = "Headless Test",
	width = 400,
	height = 300,
	visible = false,
	ns.Text "Hello",
}

t.assertEqual(win.title, "Headless Test", "Window title is set")

-- Separator is an NSBox with separator style

local s = ns.Separator()
t.assertEqual(s.boxType, 2, "Separator has NSBoxSeparator boxType")

-- Spacer can be created

local sp = ns.Spacer()
t.expect(sp ~= nil, "Spacer creates successfully")

-- Layout modifiers support SwiftUI-like stack spacing and cross-axis fill

local filled = ns.Text {
	"Fill",
	fillWidth = true,
}
t.expect(filled.fillWidth, "fillWidth is retained")

local spaced = ns.VStack {
	spacing = 3,
	paddingHorizontal = 12,
	paddingVertical = 7,
	ns.Text "One",
	ns.Text "Two",
}
t.assertEqual(spaced.spacing, 3, "custom stack spacing is retained")
t.assertEqual(spaced.paddingHorizontal, 12, "horizontal padding is retained")
t.assertEqual(spaced.paddingVertical, 7, "vertical padding is retained")

-- Image layout uses the bridge's capped display size, not the source bitmap's
-- intrinsic dimensions, and remains proportional under a narrower proposal.

local cappedImage = ns.Image "tests/fixtures/oversized.svg"
ns.Window {
	width = 480,
	height = 300,
	visible = false,
	ns.VStack {
		alignment = "leading",
		cappedImage,
	},
}
t.assertSize(cappedImage, 400, 200, "oversized image uses capped layout size")

local narrowImage = ns.Image "tests/fixtures/oversized.svg"
ns.Window {
	width = 300,
	height = 300,
	visible = false,
	ns.VStack {
		alignment = "leading",
		narrowImage,
	},
}
t.assertSize(narrowImage, 300, 150, "image scales proportionally in a narrow window")

-- ForEach composes data-driven children without adding placeholder views

ok = pcall(function()
	ns.VStack {
		ns.ForEach({ "One", "Two" }, function(value)
			return ns.Text(value)
		end),
	}
end)
t.expect(ok, "ForEach composes data-driven views")

local compound = ns.Button {
	title = "Open",
	subtitle = "A document",
	systemImage = "folder",
	style = "plain",
}
t.expect(compound ~= nil, "compound native button creates successfully")

local symbolToggle = require("bridge")._symbolToggle(
	"text.justify",
	"Toggle Word Wrap",
	false)
local secondSymbolToggle = require("bridge")._symbolToggle(
	"sidebar.right",
	"Toggle Inspector",
	false)
local controlBar = require("IDEKit").ControlBar {
	title = "EDITOR",
	buttons = { symbolToggle, secondSymbolToggle },
}
t.expect(controlBar ~= nil, "ControlBar accepts an optional trailing button array")

-- List: add, remove, clear rows

local list = ns.List {
	width = 400,
	height = 200,
	style = "plain",
	columns = {
		{
			id = "name",
			title = "Name",
			width = 200,
			systemImage = "doc.text",
		},
		{ id = "role", title = "Role", width = 200 },
	},
}

t.assertEqual(list.documentView.style, 4, "List forwards the native plain table style")

local has_add = list["addRow"] ~= nil
t.expect(has_add, "List has add_row method")

local has_clear = list["clearRows"] ~= nil
t.expect(has_clear, "List has clear_rows method")

local has_loading = list["showLoading"] ~= nil
t.expect(has_loading, "List has show_loading method")

list:clearRows()
t.assertEqual(list.rowCount, 0, "New list has zero rows")

list:addRow{ name = "Alice", role = "Engineer" }
t.assertEqual(list.rowCount, 1, "After addRow: 1 row")

list:addRow{ name = "Bob", role = "Designer" }
t.assertEqual(list.rowCount, 2, "After second addRow: 2 rows")

list:removeRow(0)
t.assertEqual(list.rowCount, 1, "After removeRow(0): 1 row")

list:clearRows()
t.assertEqual(list.rowCount, 0, "After clearRows: 0 rows")

-- Loading spinner

list:showLoading()
list:hideLoading()
t.expect(true, "show_loading and hide_loading do not crash")

-- Code editor remains a native editable text view inside its scroll view.

local editor = require("IDEKit").Editor {
	initialCode = "return 1",
}
t.assertEqual(
	editor._view.documentView.editable,
	true,
	"IDE editor text view is editable")
t.assertEqual(
	editor._view.documentView.selectable,
	true,
	"IDE editor text view is selectable")
t.assertEqual(
	editor._view.documentView.string,
	"return 1",
	"IDE editor exposes its initial source")

-- Plugin registry exposes the text editor as the first editor plugin.

t.expect(PluginKit.get("textEditor") == TextEditorPlugin,
	"text editor plugin is registered")
t.expect(PluginKit.get("imageViewer") == ImageViewerPlugin,
	"image viewer plugin is registered")
t.assertEqual(TextEditorPlugin.kind, "editor", "text editor plugin kind")
t.assertEqual(TextEditorPlugin.title, "Text Editor", "text editor plugin title")
t.assertEqual(ImageViewerPlugin.kind, "editor", "image viewer plugin kind")
t.assertEqual(ImageViewerPlugin.title, "Image Viewer", "image viewer plugin title")
t.assertEqual(
	PluginKit.resolveByFile("sample.lua", "editor"),
	TextEditorPlugin.spec,
	"plugin resolves by file extension")
t.assertEqual(
	PluginKit.resolveByFile("sample.svg", "editor"),
	ImageViewerPlugin.spec,
	"image viewer resolves by image extension")
t.assertEqual(
	PluginKit.resolveByCommand("openTextEditor", "editor"),
	TextEditorPlugin.spec,
	"plugin resolves by command")

local pluginEditor = PluginKit.use("textEditor", {
	initialCode = "return 42",
})
t.assertEqual(
	pluginEditor._view.documentView.editable,
	true,
	"text editor plugin editor is editable")
t.assertEqual(
	pluginEditor._view.documentView.string,
	"return 42",
	"text editor plugin editor exposes initial source")

local imageViewer = require("bridge")._imageViewer("tests/fixtures/oversized.svg")
t.expect(imageViewer ~= nil, "image viewer surface creates successfully")
t.assertEqual(imageViewer.zoomScale, 1, "image viewer starts at 1x zoom")
t.expect(imageViewer.fitToWindow == false, "image viewer starts in actual-size mode")
imageViewer.fitToWindow = true
t.expect(imageViewer.fitToWindow == true, "image viewer fit-to-window property is writable")
imageViewer.fitToWindow = false
imageViewer.zoomScale = 1.25
t.assertEqual(imageViewer.zoomScale, 1.25, "image viewer zoomScale is writable")
imageViewer.imagePath = "tests/fixtures/oversized.svg"
t.assertEqual(imageViewer.imagePath, "tests/fixtures/oversized.svg", "image viewer imagePath is writable")

local pluginImage = PluginKit.use("imageViewer", {
	path = "tests/fixtures/oversized.svg",
})
t.expect(pluginImage ~= nil, "image viewer plugin window creates successfully")
t.assertEqual(
	pluginImage.title,
	"oversized.svg",
	"image viewer plugin uses the file name as its title")

-- App recent-store persists and restores recents in a workspace-local path.

local recentRoot = "/private/tmp/lua-objc-app-test"
local recentStore = App.recentStore("bridge-test", {
	storageRoot = recentRoot,
	limit = 2,
})
recentStore:clear()
recentStore:recordFolder("/private/tmp/project-a", "Project A")
recentStore:recordFile("/private/tmp/project-a/main.lua", "main.lua")

local reloadedStore = App.recentStore("bridge-test", {
	storageRoot = recentRoot,
	limit = 2,
})
t.assertEqual(#reloadedStore:list(), 2, "recent store reloads saved entries")
t.assertEqual(reloadedStore:list()[1].kind, "file", "most recent entry is first")
t.assertEqual(reloadedStore:list()[2].kind, "folder", "older entry remains available")

local recentApp = App.new {
	recentKey = "bridge-test",
	storageRoot = recentRoot,
}
t.assertEqual(#recentApp:recentFiles(), 1, "recent files are filtered separately")
t.assertEqual(#recentApp:recentFolders(), 1, "recent folders are filtered separately")

local recentState = RecentState.new {
	key = "bridge-test",
	limit = 2,
	storageRoot = recentRoot,
}
t.assertEqual(#recentState:files(), 1, "recent state exposes file items")
t.assertEqual(#recentState:folders(), 1, "recent state exposes folder items")

-- fetch infrastructure exists

t.expect(ns.fetch ~= nil, "fetch function exists")
t.expect(ns.fetch_json ~= nil, "fetch_json function exists")
t.expect(ns.json_parse ~= nil, "json_parse function exists")
t.expect(ns.async ~= nil, "async function exists")
t.expect(ns.sleep ~= nil, "sleep function exists")

-- Async functions execute behind coroutine.resume, whose errors are return
-- values rather than thrown exceptions. They still need to reach stderr.

local original_stderr = io.stderr
local async_stderr = ""
io.stderr = {
	write = function(_, message)
		async_stderr = async_stderr .. message
	end,
}
ns.async(function()
	error("async boom")
end)
io.stderr = original_stderr
t.expect(
	async_stderr:find("coroutine error:", 1, true) ~= nil
		and async_stderr:find("async boom", 1, true) ~= nil,
	"async errors are written to stderr")

-- JSON parsing

local parsed = ns.json_parse('{"key": 42, "name": "test"}')
t.assertEqual(parsed.key, 42, "json_parse: numeric value")
t.assertEqual(parsed.name, "test", "json_parse: string value")

-- Canvas eval: ns.Window{...} without `return` must produce a view

local bridge_raw = require("bridge")

local view1, err1 = bridge_raw._eval("local ns=require('AppKit'); ns.Window { ns.Text 'hi' }", true)
t.expect(err1 == nil, "canvas eval: Window without return has no error")
t.expect(view1 ~= nil, "canvas eval: Window without return produces a view")

-- Canvas eval: explicit return still works

local view2, err2 = bridge_raw._eval("local ns=require('AppKit'); return ns.VStack { ns.Text 'hi' }", true)
t.expect(err2 == nil, "canvas eval: explicit return has no error")
t.expect(view2 ~= nil, "canvas eval: explicit return produces a view")

-- Canvas eval: ns.Preview{...} without `return` produces a view

local view3, err3 = bridge_raw._eval("local ns=require('AppKit'); ns.Preview { ns.Text 'preview' }", true)
t.expect(err3 == nil, "canvas eval: Preview without return has no error")
t.expect(view3 ~= nil, "canvas eval: Preview without return produces a view")

-- Canvas eval: ns.Preview with content function

local view4, err4 = bridge_raw._eval(
	"local ns=require('AppKit'); ns.Preview { content = function() return ns.Text 'hello' end }",
	true)
t.expect(err4 == nil, "canvas eval: Preview with content fn has no error")
t.expect(view4 ~= nil, "canvas eval: Preview with content fn produces a view")

-- Canvas eval: syntax error returns an error string, not a crash

local view5, err5 = bridge_raw._eval("this is not valid lua !!!!", true)
t.expect(view5 == nil, "canvas eval: syntax error yields nil view")
t.expect(err5 ~= nil, "canvas eval: syntax error yields error string")

-- Canvas eval: runtime error returns an error string

local view6, err6 = bridge_raw._eval("error('boom')", true)
t.expect(view6 == nil, "canvas eval: runtime error yields nil view")
t.expect(err6 ~= nil, "canvas eval: runtime error yields error string")

-- ns.Window is restored after canvas eval (not permanently replaced)

local ns_check = require("AppKit")
t.expect(type(ns_check.Window) == "function", "AppKit.Window is still a function after canvas eval")
t.expect(type(ns_check.Preview) == "function", "AppKit.Preview is still a function after canvas eval")

os.exit(t.summary() and 0 or 1)
