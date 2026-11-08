-- Lua Studio on a phone. The project fills the window; Studio is a layer
-- of glass over it and a sheet that unfolds from the capsule. The stage
-- and the chrome are retained templates, so a checked habit or a new turn
-- updates the views in place; the conversation renders into the sheet the
-- same way and the code page is pushed over it.
local xml = require("ui.xml")
local Template = require("ui.template")
local Chat = require("apps.studio.helpers.Chat")
local Theme = require("apps.studio.helpers.Theme")
local Model = require("test.studio-phone.Model")

local VIEWS = "test/studio-phone/views/"
local SHEET = { detents = { "medium", "large" }, largestUndimmedDetent = "medium", dragIndicator = true }

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({}, Controller)
end

function Controller:actions()
	local model = self.model
	return setmetatable({
		openChat = function() self:openChat() end,
		closeSheet = function() self:closeSheet() end,
		showCode = function() self:showCode() end,
		reloadPreview = function() self:reloadPreview() end,
		reminders = function() end,
		editDraft = function(text) model.draft = text end,
		sendMessage = function() self:send(model.draft) end,
	}, { __index = function(_, name)
		local id = name:match("^toggle_(%w+)$")
		if id then return function() self:toggle(id) end end
		local file = name:match("^selectFile_(.+)$")
		if file then return function() self:selectFile(file) end end
		for _, suggestion in ipairs(Chat.suggestions) do
			if suggestion.action == name then return function() self:send(suggestion.prompt) end end
		end
	end })
end

function Controller:stageData()
	local data = self.model:app()
	data.actions = self.actions
	return data
end

function Controller:chromeData()
	return { status = self.model:status(), brand = Theme.brand, tint = Theme.tint, actions = self.actions }
end

function Controller:chatData()
	local data = Chat.presentation({ messages = self.model.messages, draft = self.model.draft, projectTitle = Model.project.title })
	data.actions = self.actions
	return data
end

function Controller:render()
	self.stage:update(self:stageData())
	self.chrome:update(self:chromeData())
	if self.chat and not self.chat.closed then self.chat:update(self:chatData()) end
end

function Controller:toggle(id)
	self.model:toggle(id)
	-- The stage reconciles: the summary card takes the new count and
	-- progress, the rows keep their native toggles.
	self:render()
end

function Controller:reloadPreview()
	self.model.messages = {}
	self:render()
end

function Controller:openChat()
	if self.chat and not self.chat.closed then return end
	local ns = self.ns
	ns.presentSheet(function()
		local native, refs = xml.renderFile(VIEWS .. "sheets/Shell.etlua", { project = Model.project, projects = Model.projects, actions = self.actions }, ns)
		self.chatNav = refs.chatNav
		self.chat = Template.new(refs.content, VIEWS .. "sheets/Chat.etlua", ns)
		self.chat:update(self:chatData())
		return native
	end, SHEET)
end

function Controller:closeSheet()
	if self.chat and not self.chat.closed then self.ns.dismiss() end
	self.chat, self.chatNav, self.codePage, self.codeRefs = nil, nil, nil, nil
end

function Controller:showCode()
	if self.codePage then return end
	self:openChat()
	local ns = self.ns
	self.codePage = ns.pushScreen(self.chatNav, nil, function()
		local data = self.model:code()
		local page, refs = xml.renderFile(VIEWS .. "pages/Code.etlua", { code = data, syntaxRules = Chat.presentation().syntaxRules, actions = self.actions }, ns)
		self.codeRefs = refs
		return page
	end)
end

function Controller:selectFile(name)
	if not self.model:selectFile(name) or not self.codeRefs then return end
	local data = self.model:code()
	self.codeRefs.sourceCode.text = data.text
	self.codePage.title = data.name
end

function Controller:send(text)
	if not self.model:send(text) then return end
	self:render()
end

function Controller:createWindow()
	self.ns = self.ns or require("ns")
	local ns = self.ns
	self.model = Model.new(ns._readFile)
	self.actions = self:actions()
	local config, refs = xml.renderFile(VIEWS .. "layouts/Window.etlua", { app = self:stageData() }, ns)
	self.stage = Template.new(refs.stage, VIEWS .. "sections/Stage.etlua", ns)
	self.chrome = Template.new(refs.chrome, VIEWS .. "sections/Chrome.etlua", ns)
	self:render()
	return ns.Window(config)
end

return Controller
