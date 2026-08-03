local ns    = require("AppKit")
local bridge = require("AppKitNative")
local xml   = require("ui.xml")
local Model = require("examples.ide.Model")

local VIEWS = "examples/ide/views/"

local ACTIONS = {
	openFolder = function(self) self:openFolder() end,
}

local function buildFileTree(files)
	return ns.OutlineView {
		header = false,
		bordered = false,
		style = "sourceList",
		flexGrow = 1,
		columns = {
			{ id = "name", title = "Name", systemImage = "doc.text" },
		},
		data = files,
	}
end

local function buildEditor()
	return ns.TextEditor {
		language = "lua",
		wrapMode = true,
		flexGrow = 1,
	}
end

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		fileTree = nil,
		editor = nil,
		currentPath = nil,
		window = nil,
	}, Controller)
end

function Controller:openFile(path)
	if not path then return end
	local content = Model.readFile(path)
	if not content then return end

	self.currentPath = path
	self.editor.text = content
	self.editor.language = Model.languageForPath(path)

	if self._watchedPath then
		bridge._watchFile(self._watchedPath, nil)
	end
	self._watchedPath = path
	bridge._watchFile(path, function()
		local updated = Model.readFile(path)
		if updated then
			self.editor.text = updated
		end
	end)

	self.window.title = path:match("([^/]+)$") or path
end

function Controller:openFolder()
	local folder = bridge._pickFolder("Open Folder")
	if not folder then return end
	self:loadFolder(folder)
end

function Controller:loadFolder(folder)
	local files = Model.readDirectory(folder, 3)
	self.fileTree:replaceRows(files)
	self.window.title = folder:match("([^/]+)$") or folder

	self._folder = folder

	if self._folderSelectRef then
		self.fileTree:onRowSelect(nil)
	end
	self._folderSelectRef = true
	self.fileTree:onRowSelect(function(_, _, row)
		if row and row.path and not row.children then
			self:openFile(row.path)
		end
	end)
end

function Controller:createWindow()
	local cfg, refs = xml.renderFile(VIEWS .. "Window.etlua")

	for _, item in ipairs(cfg.toolbar or {}) do
		if item.action and ACTIONS[item.action] then
			local fn = ACTIONS[item.action]
			item.action = function() fn(self) end
		end
	end

	local files = {}
	local folder = _G.arg and _G.arg[1]
	if folder and folder ~= "" then
		files = Model.readDirectory(folder, 3)
		self._folder = folder
	end

	self.fileTree = buildFileTree(files)
	self.editor = buildEditor()
	cfg.sidebar = self.fileTree
	cfg.content = self.editor

	if self._folder then
		self.fileTree:onRowSelect(function(_, _, row)
			if row and row.path and not row.children then
				self:openFile(row.path)
			end
		end)
		cfg.title = self._folder:match("([^/]+)$") or self._folder
	end

	self.window = ns.Window(cfg)
	return self.window
end

return Controller
