local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("apps.studio.Model")
local Workspace = require("apps.studio.services.Workspace")
local Preview = require("apps.studio.services.Preview")
local PreviewController = require("apps.studio.controllers.PreviewController")
local ChatController = require("apps.studio.controllers.ChatController")
local RailController = require("apps.studio.controllers.RailController")
local Theme = require("apps.studio.models.Theme")
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
		rail = RailController.new(),
	}, Controller)
end

function Controller:renderPreview()
	if self.showcase then return self.preview:render(self.showcase.sources, self.showcase.entry) end
	return self.preview:render(self.model.files)
end

function Controller:selectFile(path)
	if type(path) ~= "string" or not self.model.files["demo/playground/" .. path] then return end
	self.selectedFile = path
	self:render()
end

-- The running preview is a hosted controller, not a description: it is
-- handed to the Preview view whenever the workspace draws a new one.
function Controller:reloadPreview()
	local controller, err = self:renderPreview()
	if controller then
		self.previewContent, self.status = controller, "Ready"
	else
		self.status = "Preview failed: " .. tostring(err)
	end
	self:render()
	if controller then return true end
	return nil, err
end

-- Commits the current project; the result replaces the status line.
function Controller:commitProject(message)
	local id, err
	if not self.versions then
		err = self.versionsError
		self.status = "Git unavailable: " .. tostring(err)
	else
		id, err = self.versions:record(message)
		if id == nil then self.status = "Commit failed: " .. tostring(err)
		else self.status = id and "Committed " .. id:sub(1, 7) or "No changes to commit" end
	end
	self:render()
	if id == nil then return nil, err end
	return id
end

-- What the workspace shows: the rail's mode, the stage, and the agent card
-- with the code pane, from the workspace state.
function Controller:workspaceData()
	local preview = self.previewPane:presentation(self.projects, self:iconChoices())
	preview.status = self.status or preview.status
	if self.showcase and self.showcase.conversation.status then preview.status = self.showcase.conversation.status end
	preview.chatHidden = self.chatHidden
	local code = Code.presentation(self.model.files, self.selectedFile or "Controller.lua")
	self.selectedFile = code.selected
	local chat = self.chat:presentation(self.showcase and self.showcase.conversation, code)
	chat.mode, chat.hidden, chat.treeHidden = self.mode, self.chatHidden, self.treeHidden
	return {
		rail = self.rail:presentation(self.mode),
		preview = preview,
		chat = chat,
		-- XML data bindings resolve against the root template context, even
		-- when the controls are declared in a nested partial.
		code = code,
		codeFiles = code.files,
		syntaxRules = Code.rules,
		actions = self.actions,
	}
end

function Controller:render()
	if not self.workspace then return end
	local _, refs = self.workspace:update(self:workspaceData())
	self.refs = refs
	if self.previewContent and refs.preview ~= self.previewView then
		refs.preview.content = self.previewContent
		self.previewView = refs.preview
	end
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
	local activeProject = projects[1]
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
	for _, project in ipairs(projects) do
		if project.id then project.imagePath = ns._documentPath(project.id .. "/AppIcon.png") end
	end

	self.projects, self.activeProject, self.projectWorkspace = projects, activeProject, workspace
	self.mode = "chat"
	self.actions = self:workspaceActions()
	local config, refs = xml.renderFile(VIEWS .. "Window.etlua", {canvas = Theme.canvas}, ns)
	local controller, err = self:renderPreview()
	if not controller then error("Could not render starter preview: " .. tostring(err)) end
	self.previewContent = controller
	self.workspace = Template.new(refs.workspace, VIEWS .. "Workspace.etlua", ns)
	self:render()
	self:showLatestTurn()
	return ns.Window(config)
end

-- The project menu's icon choices; the active project's is checked.
function Controller:iconChoices()
	local choices = {}
	local project = self.activeProject
	for _, choice in ipairs(Projects.iconChoices) do
		table.insert(choices, {
			title = choice.title,
			symbol = choice.symbol,
			imagePath = project and ns._documentPath(project.id .. "/ProjectIcons/" .. choice.file) or "",
			selected = project ~= nil and project.projectIcon == choice.id,
			action = "selectProjectIcon_" .. choice.id,
		})
	end
	return choices
end

function Controller:selectProjectIcon(choice)
	local ok, err = self.projectWorkspace.selectIcon(choice.id)
	if ok then
		local project = self.activeProject
		project.projectIcon, project.appIcon, project.icon = choice.id, choice.symbol, choice.symbol
		self.status = "Project icon: " .. choice.title
	else
		self.status = "Icon update failed: " .. tostring(err)
	end
	self:render()
end

-- Each action changes the workspace state and draws the workspace again.
function Controller:workspaceActions()
	local actions = {
		reloadPreview = function() self:reloadPreview() end,
		commitProject = function() self:commitProject("Update project") end,
		showChat = function() self.mode = "chat"; self:render() end,
		showCode = function() self.mode = "code"; self:render() end,
		toggleChat = function() self.chatHidden = not self.chatHidden; self:render() end,
		toggleTree = function() self.treeHidden = not self.treeHidden; self:render() end,
		selectFile = function(_, _, row) if row and row.id then self:selectFile(row.id) end end,
	}
	for _, choice in ipairs(Projects.iconChoices) do
		actions["selectProjectIcon_" .. choice.id] = function() self:selectProjectIcon(choice) end
	end
	return actions
end

-- A conversation opens at its latest turn, as SwiftUI's
-- defaultScrollAnchor(.bottom) does; the anchor holds until layout.
function Controller:showLatestTurn()
	self.refs.transcriptScroll:scrollTo("bottom", false)
end

return Controller
