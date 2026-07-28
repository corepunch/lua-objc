local ns = require("AppKit")
local bridge = require("bridge")
local App = require("App")

local canvasMod = require("examples.ide.components.canvas")
local WorkspaceLayout = require("examples.ide.components.workspace_layout")
local NavigatorArea = require("examples.ide.components.navigator_area")
local EditorArea = require("examples.ide.components.editor_area")
local PreviewArea = require("examples.ide.components.preview_area")
local SearchView = require("examples.ide.components.search_view")

local Source = {}

local WINDOW = {
	width = 1100,
	height = 680,
	minWidth = 800,
	minHeight = 500,
}

local function isLuaFile(name)
	return name:match("%.lua$") ~= nil
end

local imageExtensions = {
	png = true, jpg = true, jpeg = true, gif = true,
	tif = true, tiff = true, bmp = true, icns = true,
	svg = true, pdf = true,
}

local function isImageFile(name)
	local ext = name:match("%.([^.]+)$")
	return ext ~= nil and imageExtensions[ext:lower()] == true
end

local function isOpenableFile(name)
	return isLuaFile(name) or isImageFile(name)
end

local function filterOpenableFiles(items)
	if not items then return {} end
	local result = {}
	for _, item in ipairs(items) do
		if item.directory then
			local filtered = filterOpenableFiles(item.children)
			if #filtered > 0 or not item.children then
				item.children = #filtered > 0 and filtered or nil
				table.insert(result, item)
			end
		elseif isOpenableFile(item.name) then
			table.insert(result, item)
		end
	end
	return result
end

local function readFile(path)
	local file = io.open(path, "r")
	if not file then return nil end
	local content = file:read("*a")
	file:close()
	return content
end

local function openImage(path, app)
	local plugin = app and app:resolvePluginByFile(path, "editor")
	if not plugin then return end
	local window = plugin.create { path = path, app = app }
	if app and app.recent then app.recent:recordFile(path) end
	return window
end

local function defaultSource()
	return [=[
-- Try changing the text and see it update in the canvas
return ns.VStack {
	padding = 16,
	alignment = "leading",
	ns.Title "Hello, lua-objc",
	ns.Text {
		"Edit the code on the left. The canvas updates as you type.",
		size = 13,
		color = "secondary",
	},
	ns.Spacer(),
	ns.Button {
		title = "A Button",
		action = function() print("clicked") end,
	},
}
]=]
end

function Source.open(folder, app, initialFile)
	local rootDir = folder or "examples"
	local entries = ns.readDirectory(rootDir, 3)
	local files = filterOpenableFiles(entries)
	local tabbingIdentifier = "lua-objc.ide:" .. rootDir
	local primaryWindow = nil
	local documents = {}
	local wordWrapEnabled = false
	local openPath

	local function makeFileTree()
		local fileTree = ns.OutlineView {
			header = false,
			bordered = false,
			style = "sourceList",
			flexGrow = 1,
			columns = {
				{ id = "name", title = "Name", systemImage = "doc.text" },
			},
			data = files,
		}

		-- Selection remains ordinary source-list selection. Opening is the
		-- standard activation gesture and creates a native document window tab.
		fileTree:onRowActivate(function(list, rowIndex, rowData)
			if rowData and rowData.path and not rowData.directory then
				openPath(rowData.path)
			end
		end)
		return fileTree
	end

	local function makeDocumentWindow(path, content, visible)
		local name = path and (path:match("([^/\\]+)$") or path) or "Untitled"
		local canvas = canvasMod.Canvas()
		local preview, rebuildToolbar = PreviewArea.show {
			title = "CANVAS",
			content = canvas,
		}
		local textView = bridge._textView()
		bridge._textViewSetLanguage(textView, "lua")
		bridge._textViewSetText(textView, content or "")
		bridge._textViewSetWrapMode(textView, wordWrapEnabled)

		local version = 0
		local function evaluate(code)
			canvasMod.evalIntoCanvas(canvas, code, rebuildToolbar)
		end
		bridge._textViewOnChange(textView, function(text)
			version = version + 1
			local requestedVersion = version
			bridge._timerAfter(0.3, function()
				if requestedVersion == version then evaluate(text) end
			end)
		end)

		if path then
			bridge._watchFile(path, function()
				local updated = readFile(path)
				if not updated then return end
				bridge._textViewSetText(textView, updated)
				evaluate(updated)
			end)
		end

		local sourceEditor = EditorArea {
			title = "SOURCE EDITOR",
			editor = textView,
			preview = preview,
		}
		local workspace = WorkspaceLayout {
			navigator = NavigatorArea {
				title = rootDir:match("([^/\\]+)$") or "FILES",
				content = makeFileTree(),
			},
			editor = sourceEditor,
		}
		local window = ns.Window {
			title = name,
			width = WINDOW.width,
			height = WINDOW.height,
			minWidth = WINDOW.minWidth,
			minHeight = WINDOW.minHeight,
			tabbingMode = "preferred",
			tabbingIdentifier = tabbingIdentifier,
			visible = visible,
			ns.VStack {
				flexGrow = 1,
				spacing = 0,
				workspace,
			},
		}

		documents[#documents + 1] = {
			window = window,
			textView = textView,
			path = path,
		}
		evaluate(content or "")
		return window
	end

	local function openInEditor(path)
		local content = readFile(path)
		if not content then return end
		local window = makeDocumentWindow(path, content, false)
		if primaryWindow then
			ns.addTabbedWindow(primaryWindow, window)
		else
			primaryWindow = window
		end
		if app and app.recent then app.recent:recordFile(path) end
		return window
	end

	openPath = function(path)
		if isImageFile(path) then return openImage(path, app) end
		return openInEditor(path)
	end

	local initialContent = initialFile and readFile(initialFile) or defaultSource()
	primaryWindow = makeDocumentWindow(initialFile, initialContent, true)
	if initialFile and app and app.recent then app.recent:recordFile(initialFile) end

	-- Xcode-style Open Quickly remains a window-wide command instead of
	-- occupying a second navigator tab.
	local searchView = SearchView {
		rootDir = rootDir,
		onSelect = openPath,
	}
	ns.MenuItem {
		menu = "Find",
		title = "Open Quickly...",
		keyEquivalent = "p",
		modifiers = { "command" },
		action = function()
			searchView:show(primaryWindow)
		end,
	}

	ns.MenuItem {
		menu = "Editor",
		title = "Wrap Lines",
		keyEquivalent = "",
		modifiers = {},
		action = function()
			wordWrapEnabled = not wordWrapEnabled
			for _, document in ipairs(documents) do
				bridge._textViewSetWrapMode(
					document.textView,
					wordWrapEnabled)
			end
		end,
	}

	return primaryWindow
end

function Source.openFile(path, app)
	if isImageFile(path) then return openImage(path, app) end
	return Source.open(App.dirname(path), app, path)
end

return Source
