-- The workspace: one project open on the stage, the agent beside it, and
-- the sheets that change which project, which provider, and which keys.
-- Every action changes the state and draws the workspace again; the
-- previewed app is a hosted controller handed to the stage.
local ns = require("ns")
local xml = require("ui.xml")
local Template = require("ui.template")
local Model = require("apps.studio.Model")
local Workspace = require("apps.studio.services.Workspace")
local Preview = require("apps.studio.services.Preview")
local Agent = require("apps.studio.services.Agent")
local Device = require("apps.studio.services.Device")
local Keys = require("apps.studio.services.Keys")
local Providers = require("apps.studio.services.Providers")
local PreviewController = require("apps.studio.controllers.PreviewController")
local ChatController = require("apps.studio.controllers.ChatController")
local RailController = require("apps.studio.controllers.RailController")
local Theme = require("apps.studio.models.Theme")
local Projects = require("apps.studio.models.Projects")
local Code = require("apps.studio.models.Code")
local Chat = require("apps.studio.models.Chat")
local Settings = require("apps.studio.models.Settings")
local PluginsModel = require("apps.studio.models.Plugins")

local Controller = {}
Controller.__index = Controller

local VIEWS = "apps/studio/views/"
local SHEETS = { detents = { "large" } }

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

-- `options` inject the platform for tests: `ns`, `git`, `device`,
-- `present(sheet, detents)` and `dismiss(sheet)`.
function Controller.new(options)
	options = options or {}
	local platform = options.ns or ns
	local self = setmetatable({
		ns = platform,
		git = options.git,
		device = options.device,
		previewPane = PreviewController.new(),
		chat = ChatController.new(),
		rail = RailController.new(),
		mode = "chat",
		draft = "",
	}, Controller)
	self.present = options.present or function(sheet, detents)
		return platform.presentSheet(sheet, { parent = self.window, detents = detents })
	end
	self.dismiss = options.dismiss or function(sheet) return platform.dismiss(sheet) end
	return self
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
		self.previewContent = controller
		self:report("Ready")
	else
		self:report("Preview failed: " .. tostring(err), "problem")
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
		self:report("Git unavailable: " .. tostring(err), "problem")
	else
		id, err = self.versions:record(message)
		if id == nil then self:report("Commit failed: " .. tostring(err), "problem")
		else self:report(id and "Committed " .. id:sub(1, 7) or "No changes to commit") end
	end
	self:render()
	if id == nil then return nil, err end
	return id
end

-- The agent answering this project: its provider plugin and model.
function Controller:agentChoice()
	if not self.providers or not self.model then return nil end
	return Providers.choice(self.providers, self.model.provider, self.model.model)
end

function Controller:agentBusy()
	return self.agent ~= nil and self.agent.busy == true
end

-- Files changed since the last commit, for the rail's Commit badge.
function Controller:changedCount()
	local versions = self.versions
	if not versions or type(versions.changedCount) ~= "function" then return 0 end
	local ok, count = pcall(versions.changedCount, versions)
	return ok and count or 0
end

-- The status line and its tone: "ok" for a result, "problem" for a refusal
-- or a failure. The toolbar's activity viewer shows the symbol.
function Controller:report(status, tone)
	self.status, self.statusTone = status, tone or "ok"
end

-- The project's transcript as the chat shows it.
function Controller:conversation()
	local descriptor, modelId = self:agentChoice()
	return {
		messages = self.model and self.model.messages or {},
		draft = self.draft,
		busy = self:agentBusy(),
		status = { text = self:agentBusy() and "Thinking…" or self.status or "Ready",
			tone = self.statusTone or "ok", busy = self:agentBusy() },
		project = self.activeProject and self.activeProject.title or nil,
		projectIcon = self.activeProject and self.activeProject.icon or nil,
		agent = descriptor and { name = descriptor.title, model = modelId, icon = descriptor.symbol } or nil,
	}
end

-- What the workspace shows: the rail's mode, the stage, and the agent card
-- with the code pane, from the workspace state.
function Controller:workspaceData()
	local preview = self.previewPane:presentation()
	local code = Code.presentation(self.model.files, self.selectedFile or "Controller.lua")
	code.project = self.activeProject and self.activeProject.title or "Project"
	self.selectedFile = code.selected
	local chat = self.chat:presentation(self.showcase and self.showcase.conversation or self:conversation(), code)
	chat.mode, chat.treeHidden = self.mode, self.treeHidden
	self.actions = self:workspaceActions()
	return {
		rail = self.rail:presentation(self.mode, { commit = self:changedCount() },
			Projects.menu(self.projects, self:iconChoices())),
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
	-- The stage keeps its view across draws; the hosted controller changes
	-- when the preview reloads or another project opens, so both are compared.
	if self.previewContent and (refs.preview ~= self.previewView or self.previewShown ~= self.previewContent) then
		refs.preview.content = self.previewContent
		self.previewView, self.previewShown = refs.preview, self.previewContent
	end
	self:renderSheet()
end

-- Project metadata from Documents, falling back to the bundled copy.
function Controller:readProjectFile(path)
	local value = self.ns._documentRead(path)
	if value then return value end
	return self.ns._readFile("apps/studio/Documents/" .. path)
end

-- The project menu, with the active project checked and its artwork.
function Controller:refreshProjects(activeId)
	local platform = self.ns
	local projects = Projects.list(function(path) return self:readProjectFile(path) end,
		platform.json_parse, platform._jsonEncode, platform._documentWrite)
	for _, project in ipairs(projects) do
		project.imagePath = platform._documentPath(project.id .. "/AppIcon.png")
		project.action = "openProject_" .. project.id
		project.selected = project.id == activeId
		if project.selected then self.activeProject = project end
	end
	self.projects = projects
	return projects
end

-- Makes `workspace` the open project: its model, preview and agent.
function Controller:activate(id, workspace)
	if self.agent then self.agent:stop() end
	if self.versions and self.versions ~= workspace.versions then self.versions:close() end
	self.projectWorkspace, self.versions = workspace, workspace.versions
	self.model = Model.new(workspace.storage, workspace.seed)
	self.preview = Preview.new(self.ns, self.ns._readFile, workspace.localStorage)
	self.agent = Agent.new({
		model = self.model, providers = self.providers, keys = self.keys,
		http = self.device.http, json = self.device.json,
		preview = function() return self:reloadPreview() end,
		changed = function() self:render(); self:showLatestTurn() end,
	})
	self.selectedFile, self.draft, self.previewContent = nil, "", nil
	self:refreshProjects(id)
end

--- Opens the project in Documents/<id> on the stage.
function Controller:openProject(id)
	if self.activeProject and self.activeProject.id == id then return true end
	local ok, workspace = pcall(Workspace.open, self.ns, self.ns._readFile, self.git, id)
	if not ok then
		self:report("Could not open " .. id .. ": " .. tostring(workspace), "problem")
		self:render()
		return nil, workspace
	end
	self:activate(id, workspace)
	return self:reloadPreview()
end

--- Creates a project from a template, with its repository and first
--- commit, and opens it. `name` is what the person typed.
function Controller:createProject(name, templateId)
	local folder, err = Projects.folderName(name, self.projects)
	if not folder then return nil, err end
	local template = Projects.template(templateId)
	if not template then return nil, "Choose a template" end
	local files, filesError = Projects.templateFiles(template, self.ns._readFile)
	if not files then return nil, filesError end
	local metadata = { name = name, bundleId = Projects.bundleId(folder), appIcon = template.appIcon,
		projectIcon = Projects.defaultProjectIcon }
	local ok, workspace = pcall(Workspace.create, self.ns, self.git, folder, metadata, files)
	if not ok then return nil, tostring(workspace) end
	self:activate(folder, workspace)
	self:report("Created " .. name)
	self:reloadPreview()
	return folder
end

function Controller:createWindow()
	local platform = self.ns
	assert(platform.Preview, "Lua Studio requires the iPad runtime. Use make ipad-run.")
	self.device = self.device or Device.new(platform)
	self.git = self.git or require("Git")
	self.keys = Keys.new(self.device.keychain)
	self.providers, self.problems = Providers.load(self.device.json, self.device.documents)
	local projects = self:refreshProjects(nil)
	local workspace
	for index, project in ipairs(projects) do
		local opened = Workspace.open(platform, platform._readFile, self.git, project.id)
		if index == 1 then workspace = opened else opened.versions:close() end
	end
	assert(workspace, "No project is available")
	if not platform._documentRead("projects.json") then
		local names = {}
		for _, project in ipairs(projects) do table.insert(names, project.id) end
		local ok, err = platform._documentWrite("projects.json", platform._jsonEncode(names))
		assert(ok, err)
	end
	self:activate(projects[1].id, workspace)
	self.showcase = showcase(platform._readFile)
	if self.showcase then
		local current = self.showcase.current
		table.insert(self.projects, 1, {name = current.title, title = current.title, icon = current.icon, selected = true})
		for index = 2, #self.projects do self.projects[index].selected = nil end
	end
	local config, refs = xml.renderFile(VIEWS .. "layouts/Window.etlua", {canvas = Theme.canvas}, platform)
	local controller, err = self:renderPreview()
	if not controller then error("Could not render starter preview: " .. tostring(err)) end
	self.previewContent = controller
	self.workspace = Template.new(refs.workspace, VIEWS .. "layouts/Workspace.etlua", platform)
	self:render()
	self:showLatestTurn()
	self.window = platform.Window(config)
	return self.window
end

-- The project menu's icon choices; the active project's is checked.
function Controller:iconChoices()
	local choices = {}
	local project = self.activeProject
	for _, choice in ipairs(Projects.iconChoices) do
		table.insert(choices, {
			title = choice.title,
			symbol = choice.symbol,
			imagePath = project and self.ns._documentPath(project.id .. "/ProjectIcons/" .. choice.file) or "",
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
		self:report("Project icon: " .. choice.title)
	else
		self:report("Icon update failed: " .. tostring(err), "problem")
	end
	self:render()
end

--- Sends the composer's draft to the agent.
function Controller:send()
	if not self.agent then return nil, "No project is open" end
	local ok, err = self.agent:send(self.draft)
	if ok then
		self.draft = ""
	else
		self:report(err, "problem")
	end
	self:render()
	self:showLatestTurn()
	return ok, err
end

function Controller:undoChange()
	local ok, err = self.model:undo()
	if ok then
		self.model:message("agent", "Reverted the last change.")
		self:reloadPreview()
	else
		self:report(err, "problem")
		self:render()
	end
	return ok, err
end

-- Sheets: one at a time, each a retained page inside the shared host.
function Controller:openSheet(kind, state)
	if self.sheet then return nil end
	local host, hostRefs = xml.renderFile(VIEWS .. "sheets/SheetHost.etlua", {}, self.ns)
	self.sheetKind, self.sheetState = kind, state
	self.sheetPage = Template.new(hostRefs.page, VIEWS .. "sheets/" .. kind .. ".etlua", self.ns)
	self:renderSheet()
	self.sheet = self.present(host, SHEETS.detents)
	return self.sheet
end

function Controller:closeSheet()
	local sheet = self.sheet
	self.sheet, self.sheetPage, self.sheetKind, self.sheetState, self.sheetRefs = nil, nil, nil, nil, nil
	if sheet then self.dismiss(sheet) end
end

function Controller:renderSheet()
	if not self.sheetPage then return end
	local data = self:sheetData()
	data.actions = self.actions or self:workspaceActions()
	local _, refs = self.sheetPage:update(data)
	self.sheetRefs = refs
end

function Controller:sheetData()
	local state = self.sheetState
	if self.sheetKind == "Settings" then
		local data = Settings.presentation(self.providers, { provider = state.provider, model = state.model },
			function(id) return self.keys:has(id) end, state.keyDrafts, state.customModel)
		-- `notice`, not `error`: a template's data shares a namespace with
		-- Lua's globals, and an absent `error` would show the function.
		data.notice = state.error
		return data
	elseif self.sheetKind == "NewProject" then
		local templates = {}
		for _, template in ipairs(Projects.templates) do
			table.insert(templates, { id = template.id, title = template.title, icon = template.icon,
				caption = template.caption, selected = template.id == state.template })
		end
		return { name = state.name, folder = Projects.folderName(state.name, self.projects) or "",
			templates = templates, notice = state.error }
	elseif self.sheetKind == "Plugins" then
		return PluginsModel.presentation(self.providers, self.problems, function(id) return self.keys:has(id) end)
	end
	return {}
end

function Controller:openSettings()
	local descriptor, modelId = self:agentChoice()
	return self:openSheet("Settings", { provider = descriptor and descriptor.id, model = modelId, keyDrafts = {} })
end

function Controller:openNewProject()
	return self:openSheet("NewProject", { name = "", template = Projects.templates[1].id })
end

function Controller:openPlugins()
	return self:openSheet("Plugins", {})
end

-- Done in Settings: keys that were typed go to the keychain, and the
-- project remembers its provider and model.
function Controller:saveSettings()
	local state = self.sheetState
	for id, draft in pairs(state.keyDrafts) do
		local ok, err = self.keys:set(id, draft)
		if not ok then
			state.error = "Could not save the " .. id .. " key: " .. tostring(err)
			self:renderSheet()
			return nil, state.error
		end
	end
	local ok, err = self.model:setAgent(state.provider, state.model)
	if not ok then
		state.error = err
		self:renderSheet()
		return nil, err
	end
	local descriptor, modelId = self:agentChoice()
	self:report("Agent: " .. descriptor.title .. " · " .. modelId)
	self:closeSheet()
	self:render()
	return true
end

function Controller:submitNewProject()
	local state = self.sheetState
	local folder, err = self:createProject(state.name, state.template)
	if not folder then
		state.error = err
		self:renderSheet()
		return nil, err
	end
	self:closeSheet()
	self:render()
	return folder
end

-- Each action changes the workspace state and draws the workspace again.
function Controller:workspaceActions()
	local actions = {
		reloadPreview = function() self:reloadPreview() end,
		commitProject = function() self:commitProject("Update project") end,
		showChat = function() self.mode = "chat"; self:render() end,
		showCode = function() self.mode = "code"; self:render() end,
		toggleTree = function() self.treeHidden = not self.treeHidden; self:render() end,
		selectFile = function(_, _, row) if row and row.id then self:selectFile(row.id) end end,
		send = function() self:send() end,
		stopAgent = function() if self.agent then self.agent:stop() end end,
		editDraft = function(text) if type(text) == "string" then self.draft = text end end,
		composerCommand = function(command)
			if command == "submit" then self:send(); return true end
			return false
		end,
		undoChange = function() self:undoChange() end,
		newConversation = function() if self.agent then self.agent:reset() end end,
		newProject = function() self:openNewProject() end,
		openSettings = function() self:openSettings() end,
		openPlugins = function() self:openPlugins() end,
		closeSheet = function() self:closeSheet() end,
		createProject = function() self:submitNewProject() end,
		editProjectName = function(text)
			if self.sheetState and type(text) == "string" then
				self.sheetState.name, self.sheetState.error = text, nil
				self:renderSheet()
			end
		end,
		projectNameCommand = function(command)
			if command == "submit" and self.sheetState then self:submitNewProject(); return true end
			return false
		end,
		chooseProvider = function(index)
			local state = self.sheetState
			local descriptor = state and self.providers:list()[(tonumber(index) or 0) + 1]
			if not descriptor then return end
			state.provider, state.model, state.customModel, state.error = descriptor.id, descriptor.defaultModel, nil, nil
			self:renderSheet()
		end,
		chooseModel = function(index)
			local state = self.sheetState
			local descriptor = state and self.providers:get(state.provider)
			if not descriptor then return end
			local model = descriptor.models[(tonumber(index) or 0) + 1]
			if model then state.model, state.customModel = model.id, nil
			else state.customModel = state.customModel or "" end
			state.error = nil
			self:renderSheet()
		end,
		editModel = function(text)
			local state = self.sheetState
			if not state or type(text) ~= "string" then return end
			state.customModel = text
			if text:match("%S") then state.model = text:gsub("%s", "") end
			state.error = nil
		end,
		saveSettings = function() self:saveSettings() end,
	}
	for _, choice in ipairs(Projects.iconChoices) do
		actions["selectProjectIcon_" .. choice.id] = function() self:selectProjectIcon(choice) end
	end
	for _, suggestion in ipairs(Chat.suggestions) do
		actions["suggest_" .. suggestion.id] = function()
			self.draft = suggestion.prompt
			self:render()
			if self.refs and self.refs.composer and self.ns._focus then self.ns._focus(self.refs.composer) end
		end
	end
	for _, project in ipairs(self.projects or {}) do
		if project.id then actions["openProject_" .. project.id] = function() self:openProject(project.id) end end
	end
	for _, template in ipairs(Projects.templates) do
		actions["chooseTemplate_" .. template.id] = function()
			if self.sheetState then self.sheetState.template = template.id; self:renderSheet() end
		end
	end
	if self.providers then
		for _, descriptor in ipairs(self.providers:list()) do
			actions["editKey_" .. descriptor.id] = function(text)
				if self.sheetState and self.sheetState.keyDrafts and type(text) == "string" then
					self.sheetState.keyDrafts[descriptor.id] = text
					self.sheetState.error = nil
				end
			end
		end
	end
	return actions
end

-- A conversation opens at its latest turn, as SwiftUI's
-- defaultScrollAnchor(.bottom) does; the anchor holds until layout.
function Controller:showLatestTurn()
	if self.refs and self.refs.transcriptScroll then self.refs.transcriptScroll:scrollTo("bottom", false) end
end

return Controller
