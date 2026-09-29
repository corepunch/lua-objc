local ns = require("ns")
local xml = require("ui.xml")
local Model = require("apps.studio.Model")
local Workspace = require("apps.studio.services.Workspace")
local Preview = require("apps.studio.services.Preview")
local PreviewController = require("apps.studio.controllers.PreviewController")
local ChatController = require("apps.studio.controllers.ChatController")
local Projects = require("apps.studio.models.Projects")
local Code = require("apps.studio.models.Code")

local Controller = {}
Controller.__index = Controller

local VIEWS = "apps/studio/views/"

-- A showcase opens another bundled project with a prepared conversation,
-- so a promo capture shows Lua Studio mid-session. LUA_STUDIO_SHOWCASE
-- names a Lua file returning {project, current, files, conversation}:
-- `project` is the project folder ("demo/todo"), `current` how the project
-- menu names it, `files` its paths relative to the folder.
local function showcase(read)
	local path = os.getenv("LUA_STUDIO_SHOWCASE")
	if not path or path == "" then return nil end
	local data = assert(load(assert(read(path)), "@" .. path, "t", {}))()
	local files = {}
	for _, name in ipairs(data.files) do
		local file = data.project .. "/" .. name
		files[file] = assert(read(file))
	end
	data.sources = files
	data.entry = data.project:gsub("/", ".") .. ".init"
	return data
end

function Controller.new()
	return setmetatable({
		previewPane = PreviewController.new(),
		chat = ChatController.new(),
	}, Controller)
end

function Controller:renderPreview()
	if self.showcase then return self.preview:render(self.showcase.sources, self.showcase.entry) end
	return self.preview:render(self.model.files)
end

function Controller:selectFile(path)
	if type(path) ~= "string" then return end
	local content = self.model.files["demo/playground/" .. path]
	if not content then return end
	self.selectedFile = path
	self.refs.codeFileTitle.text = path:match("[^/]+$")
	self.refs.codeLanguage.text = Code.language(path):upper()
	self.refs.sourceCode.language = Code.language(path)
	self.refs.sourceCode.text = content
end

function Controller:reloadPreview()
	local controller, err = self:renderPreview()
	if controller then
		self.refs.preview.content = controller
		self.refs.previewStatus.text = "Ready"
		return true
	end
	self.refs.previewStatus.text = "Preview failed: " .. tostring(err)
	return nil, err
end

-- Commits the current project; the result replaces the status line.
function Controller:commitProject(message)
	if not self.versions then
		self.refs.previewStatus.text = "Git unavailable: " .. tostring(self.versionsError)
		return nil, self.versionsError
	end
	local id, err = self.versions:record(message)
	if id == nil then
		self.refs.previewStatus.text = "Commit failed: " .. tostring(err)
		return nil, err
	end
	self.refs.previewStatus.text = id and "Committed " .. id:sub(1, 7) or "No changes to commit"
	return id
end

function Controller:createWindow()
	assert(ns.Preview, "Lua Studio requires the iPad runtime. Use make ipad-run.")
	local function readProjectFile(path)
		local value = ns._documentRead(path)
		if value then return value end
		return ns._readFile("apps/studio/Documents/" .. path)
	end
	local projects = Projects.list(readProjectFile, ns.json_parse, ns._jsonEncode, ns._documentWrite)
	local workspace
	local git = require("Git")
	for index, project in ipairs(projects) do
		local opened = Workspace.open(ns, ns._readFile, git, project.id)
		if index == 1 then workspace = opened else opened.versions:close() end
	end
	assert(workspace, "No project is available")
	if not ns._documentRead("projects.json") then
		local names = {}
		for _, project in ipairs(projects) do table.insert(names, project.id) end
		local ok, err = ns._documentWrite("projects.json", ns._jsonEncode(names))
		assert(ok, err)
	end
	self.model = Model.new(workspace.storage, workspace.seed)
	self.versions = workspace.versions
	self.preview = Preview.new(ns, ns._readFile, workspace.localStorage)
	self.showcase = showcase(ns._readFile)
	if self.showcase then
		local current = self.showcase.current
		table.insert(projects, 1, {name = current.title, title = current.title, icon = current.icon, selected = true})
		for index = 2, #projects do projects[index].selected = nil end
	end

	local refs
	local config
	local preview = self.previewPane:presentation(projects)
	if self.showcase and self.showcase.conversation.status then preview.status = self.showcase.conversation.status end
	local code = Code.presentation(self.model.files, self.selectedFile or "Controller.lua")
	self.selectedFile = code.selected
	config, refs = xml.renderFile(VIEWS .. "Window.etlua", {
		preview = preview,
		chat = self.chat:presentation(self.showcase and self.showcase.conversation, code),
		-- XML data bindings resolve against the root template context, even
		-- when the controls are declared in a nested partial.
		code = code,
		codeFiles = code.files,
		syntaxRules = Code.rules,
		actions = {
			toggleChat = function()
				local focus = not refs.chatPane.hidden
				refs.chatPane.hidden = focus
				-- The stage is sized to the device beside the chat; alone,
				-- it takes the whole window.
				refs.previewPane.fixedWidth = not focus and preview.stageWidth or nil
				refs.chatVisibility.accessibilityLabel = focus and "Show Chat" or "Focus Preview"
			end,
			reloadPreview = function() self:reloadPreview() end,
			commitProject = function() self:commitProject("Update project") end,
			setMode = function(index)
				local showingCode = index ~= 0
				refs.transcriptScroll.hidden = showingCode
				refs.codePane.hidden = not showingCode
				refs.composerPane.hidden = showingCode
			end,
			toggleTree = function()
				self.treeHidden = not self.treeHidden
				refs.treePane.hidden = self.treeHidden
				refs.treeDivider.hidden = self.treeHidden
				refs.treeToggle.accessibilityLabel = self.treeHidden and "Show project tree" or "Hide project tree"
			end,
			selectFile = function(_, _, row)
				if row and row.id then self:selectFile(row.id) end
			end,
		},
	}, ns)
	local controller, err = self:renderPreview()
	if controller then
		refs.preview.content = controller
	else
		error("Could not render starter preview: " .. tostring(err))
	end
	self.refs = refs
	return ns.Window(config)
end

return Controller
