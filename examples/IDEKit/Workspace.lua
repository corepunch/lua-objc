local ns = require("AppKit")
local xml = require("ui.xml")
local bridge = require("AppKitNative")
local App = require("App")

local EditorArea = require("examples.IDEKit.EditorArea")
local NavigatorArea = require("examples.IDEKit.NavigatorArea")
local SearchView = require("examples.IDEKit.SearchView")

local VIEWS = "examples/IDEKit/views/"

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
	local wordWrapEnabled = true
	local openPath

	local function makeDocumentWindow(path, content, visible)
		local name = path and (path:match("([^/\\]+)$") or path) or "Untitled"

		local editor = EditorArea {
			language = "lua",
			wrapMode = wordWrapEnabled,
		}

		if path then
			bridge._watchFile(path, function()
				local updated = readFile(path)
				if not updated then return end
				editor.textView.text = updated
				editor.evaluate(updated)
			end)
		end

		editor.textView.text = content or ""

		local cfg = xml.renderFile(VIEWS .. "WorkspaceWindow.etlua", {
			name = name,
			tabbingId = tabbingIdentifier,
		})
		cfg.visible = visible
		cfg.sidebar = NavigatorArea {
			files = files,
			onRowSelect = function(filePath, inNewTab)
				openPath(filePath, inNewTab)
			end,
		}
		cfg.content = editor.view

		local window = ns.Window(cfg)

		documents[#documents + 1] = {
			window = window,
			editor = editor,
			path = path,
		}
		editor.evaluate(content or "")
		return window
	end

	local function recordFile(path)
		if app and app.recent then app.recent:recordFile(path) end
	end

	local function openInPrimaryEditor(path)
		local document = documents[1]
		if document.path == path then
			ns.selectWindowTab(primaryWindow)
			recordFile(path)
			return document
		end

		local content = readFile(path)
		if not content then return end
		if document.path then bridge._watchFile(document.path, nil) end

		local function reload()
			local updated = readFile(path)
			if not updated then return end
			document.editor.textView.text = updated
			document.editor.evaluate(updated)
		end

		document.editor.textView.text = content
		document.editor.textView.language = "lua"
		primaryWindow.title = path:match("([^/\\]+)$") or path
		bridge._watchFile(path, reload)
		document.editor.evaluate(content)
		document.path = path
		ns.selectWindowTab(primaryWindow)
		recordFile(path)
		return document
	end

	local function openInNewTab(path)
		for _, document in ipairs(documents) do
			if document.path == path then
				ns.selectWindowTab(document.window)
				recordFile(path)
				return document
			end
		end

		local content = readFile(path)
		if not content then return end
		local window = makeDocumentWindow(path, content, false)
		ns.addTabbedWindow(primaryWindow, window)
		recordFile(path)
		return window
	end

	openPath = function(path, inNewTab)
		if isImageFile(path) then return openImage(path, app) end
		if inNewTab then return openInNewTab(path) end
		return openInPrimaryEditor(path)
	end

	local initialContent = initialFile and readFile(initialFile) or defaultSource()
	primaryWindow = makeDocumentWindow(initialFile, initialContent, true)
	if initialFile and app and app.recent then app.recent:recordFile(initialFile) end

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
		menu = "View",
		title = "Toggle Sidebar",
		keyEquivalent = "0",
		modifiers = { "command" },
		action = function()
			local selectedWindow = primaryWindow
			if primaryWindow.tabGroup
				and primaryWindow.tabGroup.selectedWindow then
				selectedWindow = primaryWindow.tabGroup.selectedWindow
			end
			selectedWindow:toggleSidebar()
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
				document.editor.textView.wrapMode = wordWrapEnabled
			end
		end,
	}

	if _G.__headless then
		return primaryWindow, {
			documents = documents,
			openPath = openPath,
		}
	end
	return primaryWindow
end

function Source.openFile(path, app)
	if isImageFile(path) then return openImage(path, app) end
	return Source.open(App.dirname(path), app, path)
end

return Source
