local ns = require("AppKit")
local bridge = require("bridge")
local App = require("App")

local canvasMod = require("examples.ide.components.canvas")
local WorkspaceLayout = require("examples.ide.components.workspace_layout")
local NavigatorArea = require("examples.ide.components.navigator_area")
local EditorArea = require("examples.ide.components.editor_area")
local PreviewArea = require("examples.ide.components.preview_area")
local SearchView = require("examples.ide.components.search_view")
local FindInFiles = require("examples.ide.components.find_in_files")

local Source = {}

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

local function filterLuaFiles(items)
	if not items then return {} end
	local result = {}
	for _, item in ipairs(items) do
		if item.directory then
			local filtered = filterLuaFiles(item.children)
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

local function openImage(path, app)
	local plugin = app and app:resolvePluginByFile(path, "editor")
	if not plugin then return end
	local window = plugin.create { path = path, app = app }
	if app and app.recent then app.recent:recordFile(path) end
	return window
end

function Source.open(folder, app, initialFile)
	local canvas = canvasMod.Canvas()
	local plugin = app and app:getPlugin("textEditor")

	local rootDir = folder or "examples"
	local wordWrapEnabled = false
	local canvasVersion = 0

	local function makeTextView(content)
		local tv = bridge._textView()
		bridge._textViewSetLanguage(tv, "lua")
		bridge._textViewSetText(tv, content or "")
		return tv
	end

	local function wireCanvasEval(tv)
		bridge._textViewOnChange(tv, function(text)
			canvasVersion = canvasVersion + 1
			local v = canvasVersion
			bridge._timerAfter(0.3, function()
				if v ~= canvasVersion then return end
				canvasMod.evalIntoCanvas(canvas, text)
			end)
		end)
	end

	local function wireInitialEditor(tv, path)
		local currentFile = nil

		local function watchFile(fpath)
			if currentFile then bridge._watchFile(currentFile, nil) end
			currentFile = fpath
			if not fpath then return end
			bridge._watchFile(fpath, function()
				local f = io.open(fpath, "r")
				if not f then return end
				local data = f:read("*a")
				f:close()
				bridge._textViewSetText(tv, data)
			end)
		end

		return watchFile
	end

	local entries = ns.readDirectory(rootDir, 3)
	local filtered = filterLuaFiles(entries)

	local fileTree = ns.OutlineView {
		header = false,
		bordered = false,
		style = "plain",
		flexGrow = 1,
		columns = {
			{ id = "name", title = "Name", systemImage = "doc.text" },
		},
		data = filtered,
	}

	local editorArea, tabView

	local function openInEditor(path)
		local f = io.open(path, "r")
		if not f then return end
		local content = f:read("*a")
		f:close()

		local tv = makeTextView(content)
		wireCanvasEval(tv)
		local watchFile = wireInitialEditor(tv, path)

		local name = path:match("([^/\\]+)$") or path
		bridge._tabAdd(tabView, name, tv)
		local idx = bridge._tabCount(tabView)
		bridge._tabSelect(tabView, idx - 1)

		if app.recent then
			app.recent:recordFile(path)
		end

		watchFile(path)
		return idx
	end

	local function openPath(path)
		if isImageFile(path) then
			return openImage(path, app)
		end
		return openInEditor(path)
	end

	fileTree:onRowSelect(function(list, rowIndex, rowData)
		if rowData and rowData.path and not rowData.directory then
			openPath(rowData.path)
		end
	end)

	local findInFilesUI, findRoot = FindInFiles {
		rootDir = rootDir,
		onSelect = function(path)
			openPath(path)
		end,
	}

	editorArea, tabView = EditorArea {
		flexGrow = 1,
	}

	-- Add initial tab with canvas-eval-enabled editor.
	local initialCode = [=[
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
]=]
	local initialTV = makeTextView(initialCode)
	wireCanvasEval(initialTV)
	bridge._tabAdd(tabView, "Untitled", initialTV)

	bridge._tabOnChange(tabView, function(tv, idx, identifier, contentView)
		if contentView and isLuaFile(identifier) then
			-- NSTabView switched; the contentView is the new active text view.
			canvasMod.evalIntoCanvas(canvas,
				bridge._textViewGetText(contentView))
		end
	end)

	-- Word wrap in Editor menu (matches Xcode Editor → Wrap Lines).
	ns.MenuItem {
		menu = "Editor",
		title = "Wrap Lines",
		keyEquivalent = "",
		modifiers = {},
		action = function()
			wordWrapEnabled = not wordWrapEnabled
			-- Wrap the currently visible tab's text view.
			local count = bridge._tabCount(tabView)
			if count > 0 then
				-- Find the selected tab's text view.
				for i = 0, count - 1 do
					-- We track text views separately; for now wrap initialTV.
					bridge._textViewSetWrapMode(initialTV, wordWrapEnabled)
				end
			end
		end,
	}

	local window = ns.Window {
		title = "lua-objc IDE",
		width = 1100,
		height = 680,
		minWidth = 800,
		minHeight = 500,

		ns.VStack {
			flexGrow = 1,
			spacing = 0,
			WorkspaceLayout {
				navigator = NavigatorArea {
					tabs = {
						{ id = "files",
							symbol = "folder",
							tooltip = "Project Files" },
						{ id = "find",
							symbol = "magnifyingglass",
							tooltip = "Find in Files" },
					},
					selectedId = "files",
					content = {
						files = fileTree,
						find = findRoot,
					},
				},
				editor = editorArea,
				preview = PreviewArea.show {
					title = "CANVAS",
					content = canvas,
				},
			},
		},
	}

	-- Xcode-style Open Quickly (Cmd+P).
	local searchView = SearchView {
		rootDir = rootDir,
		onSelect = function(path)
			openPath(path)
		end,
	}
	ns.MenuItem {
		menu = "Find",
		title = "Open Quickly...",
		keyEquivalent = "p",
		modifiers = { "command" },
		action = function()
			searchView:show(window)
		end,
	}

	local function openInitialFile(path)
		if not path then return end
		openInEditor(path)
	end

	openInitialFile(initialFile)
	return window
end

function Source.openFile(path, app)
	if isImageFile(path) then
		return openImage(path, app)
	end
	local folder = App.dirname(path)
	return Source.open(folder, app, path)
end

return Source
