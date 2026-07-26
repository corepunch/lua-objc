local ns = require("AppKit")
local ide = require("IDEKit")
local bridge = require("bridge")
local App = require("App")

local Source = {}

local function isLuaFile(name)
	return name:match("%.lua$") ~= nil
end

local imageExtensions = {
	png = true,
	jpg = true,
	jpeg = true,
	gif = true,
	tif = true,
	tiff = true,
	bmp = true,
	icns = true,
	svg = true,
	pdf = true,
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
	local window = plugin.create {
		path = path,
		app = app,
	}
	if app and app.recent then
		app.recent:recordFile(path)
	end
	return window
end

function Source.open(folder, app, initialFile)
	local canvas = ide.Canvas()

	local editor = ide.Editor {
		canvas = canvas,
		plugin = app and app:getPlugin("textEditor"),
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

	local rootDir = folder or "examples"

	local wrapToggle = bridge._symbolToggle(
		"arrow.left.and.line.vertical.and.arrow.right",
		"Toggle Word Wrap",
		false,
		function(btn)
			local wrapped = btn.state == 1
			bridge._textViewSetWrapMode(editor._view, wrapped)
		end
	)

	local entries = ns.readDirectory(rootDir, 3)
	local filtered = filterLuaFiles(entries)

	local fileTree = ns.OutlineView {
		header = false,
		bordered = false,
		style = "plain",
		flexGrow = 1,
		columns = {
			{
				id = "name",
				title = "Name",
				systemImage = "doc.text",
			},
		},
		data = filtered,
	}

	local openInEditor

	local function openPath(path)
		if isImageFile(path) then
			return openImage(path, app)
		end
		return openInEditor(path)
	end

	openInEditor = function(path)
		local f = io.open(path, "r")
		if not f then return end
		local content = f:read("*a")
		f:close()
		bridge._textViewSetText(editor._view, content)
		ide._evalIntoCanvas(canvas, content)
		editor.watchFile(path)
		if app.recent then
			app.recent:recordFile(path)
		end
	end

	local function openInitialFile(path)
		if not path then return end
		openInEditor(path)
	end

	fileTree:onRowSelect(function(list, rowIndex, rowData)
		if rowData and rowData.path and not rowData.directory then
			openPath(rowData.path)
		end
	end)

	local window = ns.Window {
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
					content = fileTree,
				},
				editor = ide.EditorArea {
					title = "EDITOR",
					content = editor._view,
					buttons = { wrapToggle },
				},
				preview = ide.PreviewArea {
					title = "CANVAS",
					content = canvas,
				},
			},
		},
	}

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
