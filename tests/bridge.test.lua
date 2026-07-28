local ns = require("AppKit")
local t = require("TestKit")
local App = require("App")
local ControlBar = require("examples.ide.components.control_bar")
local Editor = require("examples.ide.components.editor")
local bridge = require("bridge")
local ImageViewerPlugin = require("examples.ide.plugins.image_viewer")
local TextEditorPlugin = require("examples.ide.plugins.text_editor")
local NativeControlsPlugin = require("examples.ide.plugins.native_controls")
local RecentState = require("examples.ide.state.recent")
local NavigatorArea = require("examples.ide.components.navigator_area")
local FindInFiles = require("examples.ide.components.find_in_files")
local EditorArea = require("examples.ide.components.editor_area")
local PreviewArea = require("examples.ide.components.preview_area")
local canvasMod = require("examples.ide.components.canvas")

-- Public frameworks must come from native Lua modules. A loose Lua fallback
-- would hide packaging regressions while still making require() appear to work.
t.expect(package.searchpath("AppKit", package.path) == nil,
	"AppKit has no loose-Lua module fallback")
local appkitModulePath = package.searchpath("AppKit", package.cpath)
t.expect(appkitModulePath ~= nil and appkitModulePath:match("AppKit%.dylib$") ~= nil,
	"AppKit resolves through package.cpath")

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

-- TextField: native edits and editing commands call reusable Lua callbacks.

local changedText = nil
local receivedCommand = nil
local input = ns.TextField {
	placeholder = "Search",
	accessibilityLabel = "Search",
	onChange = function(value)
		changedText = value
	end,
	onCommand = function(command)
		receivedCommand = command
		return command == "submit"
	end,
}
bridge._textFieldTestInput(input, "hello")
t.assertEqual(changedText, "hello", "TextField onChange receives native input")
t.expect(bridge._textFieldTestCommand(input, "submit"),
	"TextField onCommand can consume a native editing command")
t.assertEqual(receivedCommand, "submit",
	"TextField onCommand receives the normalized command name")

-- Borderless fields keep their native intrinsic height so a centered HStack
-- aligns visible glyphs with adjacent symbols, not merely an oversized frame.

local findInFiles, findInFilesRoot = FindInFiles {
	files = { "/project/main.lua" },
}
findInFilesRoot:setContentSize(220, 300)
findInFilesRoot:layout(220)
local _, searchIconY, _, searchIconHeight =
	findInFiles._searchIcon:frameInWindow()
local _, searchFieldY, _, searchFieldHeight =
	findInFiles._searchField:frameInWindow()
t.assertEqual(searchFieldHeight, 16,
	"borderless Find field keeps AppKit's native intrinsic text height")
t.expect(math.abs(
		(searchIconY + searchIconHeight / 2)
		- (searchFieldY + searchFieldHeight / 2)) < 0.5,
	"Find field and search symbol share the same vertical center")

-- Window with visible=false does not show

local win = ns.Window {
	title = "Headless Test",
	width = 400,
	height = 300,
	visible = false,
	ns.Text "Hello",
}

t.assertEqual(win.title, "Headless Test", "Window title is set")

-- NSWindow tabs group complete document windows through AppKit.

local tabHost = ns.Window {
	title = "Host.lua",
	width = 400,
	height = 300,
	visible = false,
	tabbingMode = "preferred",
	tabbingIdentifier = "tests.source-documents",
	ns.Text "Host",
}
local tabChild = ns.Window {
	title = "Child.lua",
	width = 400,
	height = 300,
	visible = false,
	tabbingMode = "preferred",
	tabbingIdentifier = "tests.source-documents",
	ns.Text "Child",
}
ns.addTabbedWindow(tabHost, tabChild)
t.assertEqual(ns.windowTabCount(tabHost), 2,
	"native window tab group contains both document windows")
ns.selectWindowTab(tabHost)
t.assertEqual(tabHost.tabbingIdentifier, "tests.source-documents",
	"window tabbing identifier round-trips through AppKit")
t.assertThrows(function()
	ns.Window {
		visible = false,
		tabbingMode = "custom",
	}
end, "window tabbing rejects unknown native modes")

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

-- Each native document window uses NSSplitViewController's semantic sidebar.
-- AppKit owns the window tab group; each document owns its nested code/canvas
-- NSSplitView.

local navigatorArea = NavigatorArea {
	title = "FILES",
	content = ns.Text "Files",
}
local previewArea, rebuildPreviewToolbar = PreviewArea.show {
	title = "CANVAS",
	content = canvasMod.Canvas(),
}
local editorArea = EditorArea {
	title = "SOURCE EDITOR",
	editor = ns.Text "A very wide editor surface",
	preview = previewArea,
}
local workspaceWindow = ns.Window {
	width = 1100,
	height = 680,
	visible = false,
	sidebarWidth = 240,
	sidebar = navigatorArea,
	content = editorArea,
}
local navigatorWidth = navigatorArea:size()
local editorWidth = editorArea:size()
local previewWidth = previewArea:size()
t.expect(navigatorWidth > 0, "IDE navigator split pane has a usable width")
t.expect(editorWidth > 0,
	"IDE editor split pane has a usable native width")
t.expect(previewWidth > 0,
	"IDE canvas split pane is visible initially")
local workspaceState = workspaceWindow:workspaceState()
t.assertEqual(workspaceState.controllerClass, "NSSplitViewController",
	"IDE workspace is owned by NSSplitViewController")
t.assertEqual(workspaceState.itemCount, 2,
	"workspace has sidebar and content split items")
t.expect(workspaceState.nativeSidebar,
	"navigator uses NSSplitViewItem's semantic sidebar behavior")
t.expect(workspaceState.fullHeightSidebar,
	"semantic sidebar participates in full-height window layout")
t.expect(workspaceState.hasToolbar,
	"workspace opts into native toolbar window chrome")
t.expect(workspaceState.usesUnifiedToolbar,
	"workspace toolbar lets the sidebar surround the traffic lights")
t.expect(workspaceState.safeAreaPaneHosts,
	"workspace panes consistently avoid native toolbar and tab-bar chrome")
t.expect(workspaceState.contentUsesSafeArea,
	"content pane respects the floating sidebar safe area")
t.assertEqual(workspaceState.topAccessoryCount, 0,
	"document window does not insert a custom content tab strip")

local sourceTree = ns.OutlineView {
	header = false,
	style = "sourceList",
	columns = {
		{ id = "name", title = "Name" },
	},
	data = {
		{ name = "main.lua" },
	},
}
t.assertEqual(sourceTree.className, "NSScrollView",
	"source list leaves sidebar material to NSSplitViewController")
t.expect(not sourceTree.drawsBackground,
	"source list remains transparent over native sidebar glass")

t.assertEqual(editorArea.className, "NSSplitView",
	"source editor owns a nested native split view")
t.expect(previewArea.clipsToBounds, "IDE canvas pane clips content at its divider")
rebuildPreviewToolbar({
	{ icon = "play.fill", tooltip = "Run" },
})
t.expect(previewWidth > 0,
	"document-local preview toolbar rebuild preserves canvas geometry")

local segmented = bridge._segmentedControl({
	{ "folder", "Files" },
	{ "magnifyingglass", "Find" },
}, 0)
t.assertEqual(segmented.selectedSegment, 0,
	"segmented control selection is readable through native KVC")
t.assertEqual(segmented.segmentStyle, 0,
	"segmented controls use AppKit's automatic macOS 26 style")
t.assertEqual(segmented.borderShape, 1,
	"segmented controls use macOS 26's native capsule border shape")
segmented.selectedSegment = 1
t.assertEqual(segmented.selectedSegment, 1,
	"segmented control selection is writable through native KVC")
t.assertThrows(function()
	bridge._tabCount(segmented)
end, "typed native arguments reject a view of the wrong Cocoa class")

-- Native NSTabView: add, select, remove, count.

local ntv = bridge._tabview(400, 200, "top")
t.assertEqual(ntv:tabCount(), 0, "empty tab view has zero tabs")
t.assertThrows(function()
	bridge._tabview(400, 200, "rounded")
end, "tab views reject app-defined document tab styles")

local contentA = ns.Text "Content A"
local contentB = ns.Text "Content B"
local contentC = ns.Text "Content C"

ntv:addTab("File A.lua", contentA)
ntv:addTab("File B.lua", contentB)
ntv:addTab("File C.lua", contentC)
t.assertEqual(ntv:tabCount(), 3, "three tabs added")

ntv:selectTab(0)
ntv:removeTab(0)
t.assertEqual(ntv:tabCount(), 2, "two tabs remain after removing first")

ntv:selectTab(0)
t.assertEqual(ntv:tabCount(), 2, "selection does not change count")

-- Preview tab pattern: remove + add replaces, plain add grows count.

local ptv = bridge._tabview(400, 200, "notabs")
t.assertEqual(ptv:tabCount(), 0, "preview tab view starts empty")

local function makePreviewTV(content)
	local tv = ns.TextEditor()
	tv:setText(content)
	return tv
end

local prev1 = makePreviewTV("preview 1")
ptv:addTab("p1.lua", prev1)
t.assertEqual(ptv:tabCount(), 1, "preview add: one tab")

ptv:removeTab(0)
local prev2 = makePreviewTV("preview 2")
ptv:addTab("p2.lua", prev2)
t.assertEqual(ptv:tabCount(), 1, "preview replaced: count stays 1")

local perm = makePreviewTV("permanent")
ptv:addTab("perm.lua", perm)
t.assertEqual(ptv:tabCount(), 2, "permanent added: count grows to 2")

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
local controlBar = ControlBar {
	title = "EDITOR",
	buttons = { symbolToggle, secondSymbolToggle },
}
t.expect(controlBar ~= nil, "ControlBar accepts an optional trailing button array")
local alignedControlBar = ControlBar {
	title = "CANVAS",
	height = 34,
}
t.assertEqual(alignedControlBar.fixedHeight, 35,
	"panel headers include the 34-point row and native 1-point separator")

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

list:replaceRows {
	{ name = "Carol", role = "Engineer" },
	{ name = "Drew", role = "Designer" },
}
t.assertEqual(list.rowCount, 2, "replaceRows atomically refreshes the datasource")

local selectedRowIndex = nil
local selectedRowName = nil
list:onRowSelect(function(_, rowIndex, row)
	selectedRowIndex = rowIndex
	selectedRowName = row.name
end)
list:selectRow(1)
t.assertEqual(selectedRowIndex, 1, "selectRow updates native selection")
t.assertEqual(selectedRowName, "Drew", "selection callback receives row data")

local activatedRowName = nil
list:onRowActivate(function(_, _, row)
	activatedRowName = row.name
end)
list:activateRow(0)
t.assertEqual(activatedRowName, "Carol",
	"activateRow follows the native double-click activation callback")

-- Loading spinner

list:showLoading()
list:hideLoading()
t.expect(true, "show_loading and hide_loading do not crash")

-- Code editor remains a native editable text view inside its scroll view.

local editor = Editor {
	plugin = TextEditorPlugin,
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

 t.expect(App.getPlugin("textEditor") == TextEditorPlugin,
	"text editor plugin is registered")

t.expect(App.getPlugin("imageViewer") == ImageViewerPlugin,
	"image viewer plugin is registered")
t.assertEqual(TextEditorPlugin.kind, "editor", "text editor plugin kind")
t.assertEqual(TextEditorPlugin.title, "Text Editor", "text editor plugin title")
t.assertEqual(ImageViewerPlugin.kind, "editor", "image viewer plugin kind")
t.assertEqual(ImageViewerPlugin.title, "Image Viewer", "image viewer plugin title")
t.assertEqual(NativeControlsPlugin.kind, "provider", "native controls plugin kind")
t.assertEqual(
	App.resolvePluginByFile("sample.lua", "editor"),
	TextEditorPlugin.spec,
	"plugin resolves by file extension")
t.assertEqual(
	App.resolvePluginByFile("sample.svg", "editor"),
	ImageViewerPlugin.spec,
	"image viewer resolves by image extension")
t.assertEqual(
	App.resolvePluginByCommand("openTextEditor", "editor"),
	TextEditorPlugin.spec,
	"plugin resolves by command")

local nativeControls = App.loadNativePlugin("build/ide-controls.dylib", "ide_controls")
t.expect(nativeControls and type(nativeControls.ColorWell) == "function",
	"Lua loads the optional Objective-C controls dylib")
local colorWell = NativeControlsPlugin.create { module = nativeControls }
t.expect(colorWell ~= nil, "native controls plugin creates an AppKit control")

local pluginEditor = App.usePlugin("textEditor", {
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

local pluginImage = App.usePlugin("imageViewer", {
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

-- Shared Lua/Foundation conversion preserves nested collections and scalar
-- types across ordinary KVC and invocation boundaries.

local valueCarrier = bridge._create("NSTableCellView")
local embeddedNul = "left\0right"
local largeInteger = 9007199254740993
valueCarrier.objectValue = {
	title = embeddedNul,
	enabled = true,
	count = largeInteger,
	items = { "one", 2, false },
}
local roundTrip = valueCarrier.objectValue
t.assertEqual(roundTrip.title, embeddedNul,
	"Foundation conversion preserves embedded NUL bytes")
t.assertEqual(roundTrip.enabled, true,
	"Foundation conversion preserves booleans")
t.assertEqual(roundTrip.count, largeInteger,
	"Foundation conversion preserves Lua integers above double precision")
t.assertEqual(roundTrip.items[1], "one",
	"Foundation conversion preserves nested arrays")
t.assertEqual(roundTrip.items[2], 2,
	"Foundation conversion preserves numeric array entries")
t.assertEqual(roundTrip.items[3], false,
	"Foundation conversion preserves false array entries")

local popup = bridge._create("NSPopUpButton")
popup:perform("addItemsWithTitles:", { "First", "Second" })
t.assertEqual(popup.numberOfItems, 2,
	"generic invocation converts a Lua array to NSArray")
t.assertEqual(popup.itemTitles[2], "Second",
	"KVC converts an NSArray result back to a Lua array")

valueCarrier.objectValue = "unchanged"
local cyclic = {}
cyclic.self = cyclic
local cyclicOk = pcall(function()
	valueCarrier.objectValue = cyclic
end)
t.expect(not cyclicOk, "cyclic Lua tables are rejected at the native boundary")
t.assertEqual(valueCarrier.objectValue, "unchanged",
	"failed conversion does not mutate unrelated native state")

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

-- Table columns resize proportionally when the table view is laid out at
-- a narrower width than its creation width. This mirrors the IDE canvas
-- embedding pattern: a 640-wide table must keep all columns visible when
-- squeezed into a 450-wide preview pane.
local tableList = ns.List {
	width = 640,
	height = 200,
	columns = {
		{ id = "name", title = "Name" },
		{ id = "role", title = "Role" },
		{ id = "dept", title = "Department" },
	},
	data = {
		{ name = "Alice Chen", role = "Engineer", dept = "Core" },
		{ name = "Bob", role = "Designer", dept = "UX" },
	},
}
local widths = bridge._tableColumnWidths(tableList)
t.assertEqual(#widths, 3, "three columns created")
for _, c in ipairs(widths) do
	t.expect(c.width > 0, "column '" .. c.id .. "' has positive width")
end

-- Verify column widths fit the initial 640-wide table.
-- (Content area is slightly narrower due to the vertical scroller.)
local total640 = 0
for _, c in ipairs(widths) do total640 = total640 + c.width end
t.expect(total640 > 600, "640-wide columns fill available width (" .. total640 .. ")")

-- Resize to 450 (simulates canvas pane embedding) and re-layout.
tableList:setContentSize(450, 200)
tableList:layout(450)
widths = bridge._tableColumnWidths(tableList)
local total450 = 0
for _, c in ipairs(widths) do
	t.expect(c.width > 0, "column '" .. c.id .. "' visible at 450px")
	total450 = total450 + c.width
end
t.expect(total450 < total640, "columns shrink when table is narrowed (" .. total450 .. " < " .. total640 .. ")")

-- Resize to 320 (very narrow but all columns must stay visible).
tableList:setContentSize(320, 200)
tableList:layout(320)
widths = bridge._tableColumnWidths(tableList)
local total320 = 0
for _, c in ipairs(widths) do
	t.expect(c.width > 0, "column '" .. c.id .. "' visible at 320px")
	total320 = total320 + c.width
end
t.expect(total320 < total450, "columns shrink further at 320px (" .. total320 .. " < " .. total450 .. ")")

-- Outline columns without an explicit width follow the navigator viewport.
-- The IDE constructs its file tree at the default 400 px, then NSSplitView
-- narrows it; retaining the construction width would reveal a horizontal
-- scrollbar even though the single name column is meant to stretch.
local fileTree = ns.OutlineView {
	width = 400,
	height = 200,
	header = false,
	columns = {
		{ id = "name", title = "Name", systemImage = "doc.text" },
	},
	data = {
		{ name = "project", children = {
			{ name = "a-file-with-a-long-name.lua" },
		} },
	},
}
fileTree:setContentSize(220, 200)
fileTree:layout(220)
local outlineWidths = bridge._tableColumnWidths(fileTree)
t.assertEqual(#outlineWidths, 1, "file tree has one outline column")
t.assertEqual(outlineWidths[1].width, 220,
	"file tree column shrinks to the navigator viewport")
t.expect(not fileTree.hasHorizontalScroller,
	"stretching file tree does not show a horizontal scroller")

-- HSplit respects fixedWidth on children (no proportions configured).

local leftFix = ns.Text {
	fixedWidth = 150,
	text = "sidebar",
}
local rightFlex = ns.Text {
	flexGrow = 1,
	text = "content",
}
local splitView = ns.HSplit {
	leftFix,
	rightFlex,
}

-- Set a known content size and run layout.
-- NSSplitView initial width matches the first subview's frame; we force a
-- specific width so the proportions kick in with a deterministic total.
splitView:setContentSize(620, 300)
splitView:layout(620)

local leftW, _ = leftFix:size()
local rightW, _ = rightFlex:size()
t.assertEqual(leftW, 150, "fixed-width pane retains 150 px in HSplit (got " .. leftW .. ")")
t.expect(rightW > 400, "flexible pane fills remaining width (got " .. rightW .. ")")

-- Simulate a window resize and verify the fixed pane does not change.
splitView:setContentSize(900, 300)
splitView:layout(900)

leftW, _ = leftFix:size()
rightW, _ = rightFlex:size()
t.assertEqual(leftW, 150, "fixed-width pane still 150 px after resize (got " .. leftW .. ")")
t.expect(rightW > leftW, "flexible pane absorbs resize (right " .. rightW .. " > left " .. leftW .. ")")

-- Table column flex: columns without width stretch; fixed columns stay fixed.

local flexTable = ns.List {
	width = 600,
	height = 200,
	columns = {
		{ id = "a", title = "FixedA", width = 120 },
		{ id = "b", title = "Stretch" },
		{ id = "c", title = "FixedC", width = 80, minWidth = 50 },
	},
	data = {
		{ a = "Alice", b = "Some subject text",  c = "Now" },
		{ a = "Bob",   b = "Another subject",    c = "10:32" },
		{ a = "Carol", b = "Long subject here",   c = "Yesterday" },
	},
}

-- Measure initial column widths at 600 px.
local function colWidth(cols, id)
	for _, c in ipairs(cols) do
		if c.id == id then return c.width end
	end
	return 0
end

flexTable:setContentSize(600, 200)
flexTable:layout(600)
local cw = bridge._tableColumnWidths(flexTable)
local a1 = colWidth(cw, "a")
local b1 = colWidth(cw, "b")
local c1 = colWidth(cw, "c")

t.assertEqual(a1, 120, "fixed column 'a' at 120 px (got " .. a1 .. ")")
t.assertEqual(c1, 80, "fixed column 'c' at 80 px (got " .. c1 .. ")")
local expectedB1 = 600 - 120 - 80
t.assertEqual(b1, expectedB1, "stretch column fills remaining " .. expectedB1 .. " px (got " .. b1 .. ")")

-- Resize wider: fixed columns must NOT change.
flexTable:setContentSize(800, 200)
flexTable:layout(800)
cw = bridge._tableColumnWidths(flexTable)
local a2 = colWidth(cw, "a")
local b2 = colWidth(cw, "b")
local c2 = colWidth(cw, "c")

t.assertEqual(a2, 120, "fixed 'a' unchanged at 120 after widen (got " .. a2 .. ")")
t.assertEqual(c2, 80, "fixed 'c' unchanged at 80 after widen (got " .. c2 .. ")")
t.expect(b2 > b1, "stretch column 'b' grew (was " .. b1 .. ", now " .. b2 .. ")")

-- Resize narrower: fixed columns must NOT change; stretch column shrinks.
flexTable:setContentSize(400, 200)
flexTable:layout(400)
cw = bridge._tableColumnWidths(flexTable)
local a3 = colWidth(cw, "a")
local b3 = colWidth(cw, "b")
local c3 = colWidth(cw, "c")

t.assertEqual(a3, 120, "fixed 'a' unchanged at 120 after narrow (got " .. a3 .. ")")
t.assertEqual(c3, 80, "fixed 'c' unchanged at 80 after narrow (got " .. c3 .. ")")
t.expect(b3 < b2, "stretch column 'b' shrank (was " .. b2 .. ", now " .. b3 .. ")")

-- Verify total fills viewport.
t.assertEqual(a3 + b3 + c3, 400,
	"columns sum to viewport width (120+" .. b3 .. "+80=" .. (a3+b3+c3) .. ")")

-- Mailbox: source list with name (stretch) + count (fixed 45 px).
-- At table width 170, count column must be present and visible.
local mailbox = ns.List {
	width = 170,
	height = 200,
	header = false,
	style = "sourceList",
	columns = {
		{ id = "name" },
		{ id = "count", width = 45, alignment = "trailing" },
	},
	data = {
		{ name = "Inbox",  count = "8" },
		{ name = "Sent",   count = "" },
	},
}
t.assertEqual(mailbox.className, "NSScrollView",
	"source-list tables do not insert a visual-effect wrapper")
t.expect(not mailbox.drawsBackground,
	"source-list table scroll view is transparent")

mailbox:setContentSize(170, 200)
mailbox:layout(170)
cw = bridge._tableColumnWidths(mailbox)
local nameW = colWidth(cw, "name")
local countW = colWidth(cw, "count")
local cellFrames = bridge._tableCellFrames(mailbox, 0)
local countFrame = cellFrames[2]

t.assertEqual(countW, 45, "mailbox count column at 45 px (got " .. countW .. ")")
t.expect(nameW < 125, "mailbox name column reserves native source-list inset")
t.assertEqual(countFrame.id, "count", "mailbox second rendered cell is count")
t.expect(countFrame.maxX <= 170,
	"mailbox count cell stays inside viewport (maxX " .. countFrame.maxX .. ")")

os.exit(t.summary() and 0 or 1)
