local xml = require("ui.xml")
local Template = require("ui.template")
local DataModel = require("data.model")
local Session = require("apps.studio.services.Session")
local Catalog = require("apps.studio.services.Catalog")
local Device = require("apps.studio.services.Device")
local Export = require("apps.studio.services.Export")
local Preview = require("apps.studio.services.Preview")
local PreviewController = require("apps.studio.controllers.PreviewController")
local ChatController = require("apps.studio.controllers.ChatController")
local RailController = require("apps.studio.controllers.RailController")
local GitHubController = require("apps.studio.controllers.GitHubController")
local SheetController = require("apps.studio.controllers.SheetController")
local Theme = require("apps.studio.helpers.Theme")
local Projects = require("apps.studio.services.Projects")
local Code = require("apps.studio.helpers.Code")
local Store = require("apps.studio.Store")
local PREFIX = "demo/playground/"
local Controller = {}
Controller.__index = Controller
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

function Controller.new(options)
	options = options or {}
	return setmetatable({ ns = options.ns, store = Store(), catalog = options.catalog,
		device = options.device, sheets = options.sheets, previewFactory = options.previewFactory,
		previewPane = PreviewController.new(), chat = ChatController.new(), rail = RailController.new(),
		mode = "chat", previewAppearance = "system", previewZoom = 1 }, Controller)
end

function Controller:renderPreview()
	if self.showcase then return self.preview:render(self.showcase.sources, self.showcase.entry) end
	return self.preview:render(self.model.files)
end

function Controller:saveSource()
	local ok, err = self.session:saveDrafts()
	self.status = ok and "Saved" or tostring(err)
	self:render()
	return ok, err
end

function Controller:reloadPreview()
	if self.session then
		local saved, err = self.session:saveDrafts()
		if not saved then self.status = tostring(err); self:render(); return nil, err end
	end
	local controller, err = self:renderPreview()
	if controller then self.previewContent, self.status = controller, "Ready"
	else self.status = "Preview failed: " .. tostring(err) end
	self:render()
	if controller then return true end
	return nil, err
end

function Controller:selectFile(path)
	if type(path) ~= "string" or not self.model.files[PREFIX .. path] then return end
	self.selectedFile = path
	self:render()
end

function Controller:commitProject(message)
	if not self.versions then self.status = "No project repository"; self:render(); return nil, self.status end
	if self.session then
		local saved, err = self.session:saveDrafts()
		if not saved then self.status = tostring(err); self:render(); return nil, err end
	end
	local id, err = self.versions:record(message)
	if id == nil then self.status = "Commit failed: " .. tostring(err)
	else self.status = id and "Committed " .. id:sub(1, 7) or "No changes to commit" end
	self:render()
	return id, err
end

function Controller:openProject(id)
	if self.github and self.github.busy then self.status = "Finish or cancel the GitHub operation first"; self:render(); return nil, self.status end
	DataModel.bind(self.store)
	local projects, found = self.catalog:list(), false
	for _, project in ipairs(projects) do if project.id == id then found = true end end
	if not found then self.status = "Choose a project from the project menu"; self:render(); return nil, self.status end
	if self.session then
		local ok, err = self.session:saveDrafts()
		if not ok then self.status = "Save or undo your edits first: " .. tostring(err); self:render(); return nil, err end
	end
	self.chat:stop()
	local ok, workspace = pcall(self.catalog.open, self.catalog, id)
	if not ok then self.status = tostring(workspace); self:render(); return nil, self.status end
	if self.versions then self.versions:close() end
	self.projects, self.activeProject = projects, nil
	for _, project in ipairs(self.projects) do
		project.selected = project.id == id
		if project.selected then self.activeProject = project end
		project.action = "openProject_" .. project.id
		if self.ns._documentExists(project.id .. "/AppIcon.png") then
			project.imagePath = self.ns._documentPath(project.id .. "/AppIcon.png")
		end
	end
	self.projectWorkspace, self.versions = workspace, workspace.versions
	self.session = Session.open(workspace.storage, workspace.seed, id)
	self.model = self.session.workspace
	if self.preview then self.preview:close() end
	self.preview = self.previewFactory and self.previewFactory(workspace)
		or Preview.new(self.ns, self.ns._readFile, workspace.localStorage)
	self.previewContent, self.previewView, self.renderedPreviewContent = nil, nil, nil
	self.selectedFile, self.showcase = "Controller.lua", nil
	self.actions = self:workspaceActions()
	self.chat:attach(self.session, self.device, function() return self:reloadPreview() end,
		DataModel.bound(self.store, function() self:render(); self:showLatestTurn() end),
		function(action, value) return self.preview:interact(action, value) end)
	self:reloadPreview()
	return true
end

function Controller:workspaceData()
	if not self.model then return {empty = true, status = self.status or "", actions = self.actions} end
	local preview = self.previewPane:presentation(self.projects, self:iconChoices())
	preview.status, preview.chatHidden = self.status or preview.status, self.chatHidden
	preview.failed = self.preview and self.preview.lastError ~= nil
	preview.appearance, preview.zoomValue = self.previewAppearance, self.previewZoom
	preview.zoom = self.previewZoom == 1 and "Fit" or "75%"
	local code = Code.presentation(self.model.files, self.selectedFile or "Controller.lua")
	self.selectedFile = code.selected
	if code.selected then code.text = self.model:source(PREFIX .. code.selected) end
	local chat = self.chat:presentation(self.showcase and self.showcase.conversation, code)
	chat.mode, chat.hidden, chat.treeHidden = self.mode, self.chatHidden, self.treeHidden
	chat.projectTitle = self.activeProject and self.activeProject.title or "Project"
	return { rail = self.rail:presentation(self.mode), preview = preview, chat = chat,
		code = code, codeFiles = code.files, syntaxRules = Code.rules, actions = self.actions }
end

function Controller:render()
	if not self.workspace then return end
	local _, refs = self.workspace:update(self:workspaceData())
	self.refs = refs
	if not refs.preview then return end
	if refs.preview ~= self.previewView or self.renderedPreviewContent ~= self.previewContent then
		if self.previewContent or self.renderedPreviewContent then refs.preview.content = self.previewContent end
		self.previewView, self.renderedPreviewContent = refs.preview, self.previewContent
	end
end

function Controller:createWindow()
	self.ns = self.ns or require("ns")
	local ns = self.ns
	assert(ns.Preview, "Lua Studio requires the iPad runtime. Use make ipad-run.")
	DataModel.bind(self.store)
	self.catalog = self.catalog or Catalog.new(ns, require("Git"), ns._readFile)
	self.device = self.device or Device.new(ns)
	self.sheets = self.sheets or SheetController.new(ns)
	self.github = self.github or GitHubController.new(self, self.device.github)
	local projects = self.catalog:list()
	if projects[1] then assert(self:openProject(projects[1].id))
	else self.projects = projects; self.actions = self:workspaceActions() end
	self.showcase = showcase(ns._readFile)
	if self.showcase then self:reloadPreview() end
	local config, refs = xml.renderFile("apps/studio/views/layouts/Window.etlua", {canvas = Theme.canvas}, ns)
	self.workspace = Template.new(refs.workspace, "apps/studio/views/sections/Workspace.etlua", ns)
	self:render()
	self:showLatestTurn()
	return ns.Window(config)
end

function Controller:iconChoices()
	local choices = {}
	local project = self.activeProject
	for _, choice in ipairs(Projects.iconChoices) do
		table.insert(choices, {title = choice.title, symbol = choice.symbol,
			imagePath = project and self.ns._documentPath(project.id .. "/ProjectIcons/" .. choice.file) or "",
			selected = project ~= nil and project.projectIcon == choice.id, action = "selectProjectIcon_" .. choice.id})
	end
	return choices
end

function Controller:selectProjectIcon(choice)
	local ok, err = self.projectWorkspace.selectIcon(choice.id)
	if ok then
		local project = self.activeProject
		project.projectIcon, project.appIcon, project.icon = choice.id, choice.symbol, choice.symbol
		self.status = "Project icon: " .. choice.title
	else self.status = "Icon update failed: " .. tostring(err) end
	self:render()
end

function Controller:showLatestTurn()
	if self.refs and self.refs.transcriptScroll then self.refs.transcriptScroll:scrollTo("bottom", false) end
end

function Controller:showSheet(kind, data)
	self.chat:stopDictation()
	self.sheetKind, self.sheetData = kind, data
	data.actions = self.actions
	self.sheets:present(kind, data)
end

function Controller:updateSheet(message)
	self.sheetData.message = message or ""
	self.sheets:update(self.sheetData)
end

function Controller:closeSheet()
	self.sheets:close()
	self.sheetData, self.sheetKind = nil, nil
end

function Controller:showSettings()
	local key = self.device.credentials.read()
	self:showSheet("Settings", {title = "Settings", keyDraft = "", hasKey = key ~= nil,
		modelIdDraft = self.model.modelId, message = ""})
end

function Controller:showNewProject(template)
	self:showSheet("Project", {title = "New Project", projectName = "", templateIndex = template == "HabitTracker" and 1 or 0, message = ""})
end

function Controller:createProject()
	local data = self.sheetData
	if self.github and self.github.busy then self:updateSheet("Finish or cancel the GitHub operation first"); return nil end
	if self.session then
		local saved, err = self.session:saveDrafts()
		if not saved then self:updateSheet("Save or undo your edits first: " .. tostring(err)); return nil, err end
	end
	local created, err = self.catalog:create(data.projectName, data.templateIndex == 1 and "HabitTracker" or "StarterApp")
	if not created then self:updateSheet(err); return nil, err end
	-- Catalog creation has already initialized Git; reopen through the same
	-- path as every project so the controller owns just one repository handle.
	created.workspace.versions:close()
	self:closeSheet()
	return self:openProject(created.id)
end

function Controller:showDeleteProject()
	if not self.activeProject then return end
	if self.github and self.github.busy then self.status = "Finish or cancel the GitHub operation first"; self:render(); return nil end
	self.chat:stopDictation()
	local id = self.activeProject.id
	return self.ns.confirm({title = 'Delete “' .. self.activeProject.title .. '”?',
		message = "This removes its source, unsaved edits, local data and Git history from this iPad. The GitHub copy stays intact.",
		destructive = "Delete Project", cancel = "Cancel",
		action = DataModel.bound(self.store, function() return self:deleteProject(id) end)})
end

function Controller:deleteProject(id)
	DataModel.bind(self.store)
	if not self.activeProject or id ~= self.activeProject.id then return nil end
	if self.github and self.github.busy then self.status = "Finish or cancel the GitHub operation first"; self:render(); return nil end
	self.chat:stop()
	local ok, err = self.catalog:delete(self.activeProject.id)
	if not ok then self.status = "Delete failed: " .. tostring(err); self:render(); return nil, err end
	self.versions:close()
	self.preview:close()
	self.model:delete()
	self.session, self.model, self.projectWorkspace, self.versions, self.activeProject, self.preview = nil, nil, nil, nil, nil, nil
	self.previewContent, self.previewView, self.renderedPreviewContent = nil, nil, nil
	self.chat = ChatController.new()
	self.projects = self.catalog:list()
	if self.projects[1] then
		local opened, detail = self:openProject(self.projects[1].id)
		if not opened then self.status = detail end
	end
	self.status = "Project deleted from this iPad"
	self.actions = self:workspaceActions()
	self:render()
	return true
end

function Controller:showCatalog(kind)
	local items
	if kind == "Templates" then
		items = {
			{title = "Blank App", detail = "A native screen with a Lapis model, controller and etlua views.", icon = "doc.badge.plus", button = "Create…", action = "newBlank"},
			{title = "Habit Tracker", detail = "Start from Today, Stats, Settings and local app data.", icon = "checklist", button = "Create…", action = "newHabit"},
		}
	elseif kind == "Examples" then
		items = {}
		for _, project in ipairs(self.projects) do
			table.insert(items, {title = project.title, detail = project.bundleId, icon = project.icon,
				button = "Open", action = "openProject_" .. project.id})
		end
	else
		items = {
			{title = "Git", detail = "Local commits and project history. Included and active.", icon = "point.3.connected.trianglepath.dotted"},
			{title = "Speech", detail = "System dictation. Microphone and speech access are requested when you start dictation.", icon = "mic"},
			{title = "UIKit", detail = "Native Apple controls supplied by the host. New native plugins need a host build.", icon = "square.stack.3d.up"},
		}
	end
	self:showSheet("Catalog", {title = kind, items = items})
end

function Controller:shareProject()
	self.chat:stopDictation()
	local ok, err = self.session:saveDrafts()
	if ok then ok, err = Export.share(self.ns, self.activeProject, self.model.files) end
	if not ok then self.status = tostring(err); self:render() end
	return ok, err
end

function Controller:sendMessage()
	local ok, err, code = self.chat:send()
	if not ok then
		self.status = tostring(err)
		if code == "credentials" then self:showSettings() end
		self:render()
	end
	return ok, err
end

function Controller:workspaceActions()
	local actions = {
		reloadPreview = function() return self:reloadPreview() end,
		saveSource = function() return self:saveSource() end,
		editSource = function(text)
			if self.chat.agent.busy then return end
			local ok, err = self.model:edit(PREFIX .. self.selectedFile, text)
			if not ok then self.status = err; self:render() end
		end,
		commitProject = function() return self:commitProject("Update project") end,
		showChat = function() self.mode = "chat"; self:render() end,
		showCode = function() self.chat:stopDictation(); self.mode = "code"; self:render() end,
		toggleChat = function() self.chatHidden = not self.chatHidden; if self.chatHidden then self.chat:stopDictation() end; self:render() end,
		toggleTree = function() self.treeHidden = not self.treeHidden; self:render() end,
		selectFile = function(_, _, row) if row and row.id then self:selectFile(row.id) end end,
		editDraft = function(text) self.chat.draft = text end,
		sendMessage = function() return self:sendMessage() end,
		composerCommand = function(command) if command == "submit" then return self:sendMessage() end end,
		removeAttachments = function() self.chat.attachments = {}; self:render() end,
		attachContext = function()
			self.chat:stopDictation()
			self.device.importText(DataModel.bound(self.store, function(files, err)
				if files then local ok; ok, err = self.chat:attachFiles(files) end
				if err then self.status = err; self:render() end
			end))
		end,
		toggleDictation = function()
			local ok, err = self.chat:toggleDictation()
			if not ok and err then self.status = err; self:render() end
		end,
		stopAgent = function() self.chat:stop() end,
		newConversation = function() self.chat:newConversation() end,
		undoChange = function()
			local ok, err = self.session:undo()
			if ok then self:reloadPreview() else self.status = err; self:render() end
		end,
		showGitHub = function() self.github:show() end,
		editGitHubToken = function(value) self.github:edit("tokenDraft", value) end,
		editGitHubOwner = function(value) self.github:edit("owner", value) end,
		editGitHubRepository = function(value) self.github:edit("repository", value) end,
		editGitHubBranch = function(value) self.github:edit("branch", value) end,
		editGitHubPrivate = function(value) self.github:edit("private", value) end,
		editGitHubName = function(value) self.github:edit("name", value) end,
		editGitHubEmail = function(value) self.github:edit("email", value) end,
		connectGitHub = function() return self.github:connect() end,
		disconnectGitHub = function() return self.github:disconnect() end,
		createGitHubRepository = function() return self.github:link(true) end,
		linkGitHubRepository = function() return self.github:link(false) end,
		publishGitHub = function() return self.github:publish() end,
		cancelGitHub = function() self.github:cancel() end,
		showSettings = function() self:showSettings() end,
		showTemplates = function() self:showCatalog("Templates") end,
		showExamples = function() self:showCatalog("Examples") end,
		showPlugins = function() self:showCatalog("Plugins") end,
		newProject = function() self:showNewProject() end,
		showDeleteProject = function() return self:showDeleteProject() end,
		newBlank = function() self:showNewProject("StarterApp") end,
		newHabit = function() self:showNewProject("HabitTracker") end,
		closeSheet = function() self:closeSheet() end,
		editProjectName = function(text) self.sheetData.projectName = text end,
		chooseTemplate = function(index) self.sheetData.templateIndex = index end,
		createProject = function() return self:createProject() end,
		editKey = function(text) self.sheetData.keyDraft = text end,
		editModel = function(text) self.sheetData.modelIdDraft = text end,
		saveCredential = function()
			local ok, err = self.device.credentials.save(self.sheetData.keyDraft)
			if ok then self.sheetData.keyDraft, self.sheetData.hasKey = "", true end
			self:updateSheet(ok and "API key saved in Keychain." or err)
		end,
		clearCredential = function()
			local ok, err = self.device.credentials.clear()
			if ok then self.sheetData.keyDraft, self.sheetData.hasKey = "", false end
			self:updateSheet(ok and "Saved API key removed." or err)
		end,
		saveModel = function()
			local ok, err = self.session:setModel(self.sheetData.modelIdDraft)
			self:updateSheet(ok and "Model saved." or err)
			self:render()
		end,
		shareProject = function() return self:shareProject() end,
		showExport = function() self:showSheet("Export", {title = "Export Project", projectTitle = self.activeProject.title}) end,
		exportProject = function() self:closeSheet(); return self:shareProject() end,
		toggleAppearance = function()
			self.previewAppearance = self.previewAppearance == "dark" and "light" or "dark"
			self:render()
		end,
		toggleZoom = function() self.previewZoom = self.previewZoom == 1 and 0.75 or 1; self:render() end,
	}
	for _, choice in ipairs(Projects.iconChoices) do actions["selectProjectIcon_" .. choice.id] = function() self:selectProjectIcon(choice) end end
	for _, project in ipairs(self.projects or {}) do
		actions["openProject_" .. project.id] = function()
			if self.sheetKind then self:closeSheet() end
			return self:openProject(project.id)
		end
	end
	for _, suggestion in ipairs(self.chat.model.suggestions) do
		actions[suggestion.action] = function() self.chat.draft = suggestion.prompt; self:render() end
	end
	for name, action in pairs(actions) do actions[name] = DataModel.bound(self.store, action) end
	return actions
end
return Controller
