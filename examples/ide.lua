local ns = require("AppKit")
local ide = require("IDEKit")
local bridge = require("bridge")

-- Canvas: inline preview host — matches Xcode's macOS preview architecture.
-- ns.Window is intercepted by _evalIntoCanvas → content-only VStack, no chrome.
local canvas = ide.Canvas()

local editor = ide.Editor {
	canvas = canvas,
	initialCode = [=[
-- Try changing the text and see it update in the canvas
return ns.VStack {
	padding = 16,
	alignment = "leading",
	ns.Title "Hello, lua-objc",
	ns.Text {
		"Edit the code in the center. The canvas updates as you type.",
		size = 13,
		color = "secondary",
	},
	ns.Spacer(),
	ns.Button {
		title = "A Button",
		action = function() print("clicked") end,
	},
}
]=],
}

local files = {
	{ name = "hello.lua" },
	{ name = "list.lua" },
	{ name = "live.lua" },
	{ name = "weather.lua" },
	{ name = "mail.lua" },
	{ name = "welcome.lua" },
}

-- File tree: NSTableView acting as a source-list navigator.
-- Mirrors Xcode's DVTExplorerOutlineView inside IDENavigatorArea.
local fileTree = ns.List {
	header = false,
	bordered = false,
	flexGrow = 1,
	columns = {
		{
			id = "name",
			title = "Name",
			systemImage = "doc.text",
		},
	},
	data = files,
}

local examplesDir = "examples"

local function openInEditor(filename)
	local path = examplesDir .. "/" .. filename
	local f = io.open(path, "r")
	if not f then return end
	local content = f:read("*a")
	f:close()
	bridge._textViewSetText(editor._view, content)
	ide._evalIntoCanvas(canvas, content)
	editor.watchFile(path)
end

fileTree:onRowSelect(function(list, rowIndex, rowData)
	if rowData and rowData.name then
		openInEditor(rowData.name)
	end
end)

-- WorkspaceLayout: root HSplit with three areas:
--   NavigatorArea (left)  → IDENavigatorArea
--   EditorArea   (centre) → IDEEditorArea
--   PreviewArea  (right)  → inline macOS preview canvas
-- This mirrors the Xcode workspace root NSSplitView structure.
return ns.Window {
	title = "lua-objc IDE",
	width = 1100,
	height = 680,
	minWidth = 800,
	minHeight = 500,

	ns.VStack {
		flexGrow = 1,
		spacing = 0,
		ide.WorkspaceLayout {
			navigator = ide.NavigatorArea {
				title = "FILES",
				fixedWidth = 160,
				content = fileTree,
			},
			editor = ide.EditorArea {
				title = "EDITOR",
				content = editor._view,
			},
			preview = ide.PreviewArea {
				title = "CANVAS",
				content = canvas,
			},
		},
	},
}
