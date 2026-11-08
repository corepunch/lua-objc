-- Lua Studio on a phone. The project fills the screen and Studio is the
-- capsule in its tab bar (floating above a project without one), which
-- unfolds the conversation as a sheet with the running project visible
-- beneath; the code is pushed in that sheet. This controller coordinates
-- those presentations over the root controller's session, agent and
-- preview. It computes no data of its own: the capsule reads the
-- conversation, the sheet renders the same chat presentation as the iPad.
local xml = require("ui.xml")
local Template = require("ui.template")
local DataModel = require("data.model")
local Capsule = require("apps.studio.helpers.Capsule")
local Code = require("apps.studio.helpers.Code")
local Theme = require("apps.studio.helpers.Theme")

local VIEWS = "apps/studio/views/"
-- Apple Maps: the sheet rests at half height with the project live beneath.
local SHEET = { detents = { "medium", "large" }, largestUndimmedDetent = "medium", dragIndicator = true }

local Phone = {}
Phone.__index = Phone

function Phone.new(root, ns)
	return setmetatable({ root = root, ns = ns }, Phone)
end

-- The window config for the root, which alone creates the window.
function Phone:windowConfig()
	local ns = self.ns
	local config, refs = xml.renderFile(VIEWS .. "layouts/Phone.etlua", {}, ns)
	self.stage = refs.stage
	self.capsule = Template.new(refs.chrome, VIEWS .. "sections/Capsule.etlua", ns)
	self:render()
	return config
end

function Phone:busy()
	local agent = self.root.chat.agent
	return agent ~= nil and agent.busy == true
end

function Phone:capsuleData()
	local root = self.root
	local data = Capsule.status({
		messages = root.model and root.model.messages or {},
		busy = self:busy(),
		project = root.activeProject,
		modelId = root.model and root.model.modelId,
		previewError = root.preview and root.preview.lastError,
	})
	data.brand, data.tint, data.actions = Theme.brand, Theme.tint, root.actions
	return data
end

function Phone:conversationData()
	local root = self.root
	local data = root:chatData(root:codeData())
	data.actions = root.actions
	return data
end

function Phone:editorData()
	local root = self.root
	return { code = root:codeData(), syntaxRules = Code.rules, busy = self:busy(), actions = root.actions }
end

function Phone:shellData()
	local root = self.root
	return { project = root.activeProject, modelId = root.model.modelId, projects = root.projects or {}, actions = root.actions }
end

function Phone:conversationOpen()
	return self.conversation ~= nil and not self.conversation.closed
end

function Phone:render()
	local root = self.root
	if self.capsule then self.capsule:update(self:capsuleData()) end
	if self:conversationOpen() and root.model then
		local _, refs = self.conversation:update(self:conversationData())
		self.conversationRefs = refs
	end
	if self.editor and not self.editor.closed and root.model then self.editor:update(self:editorData()) end
	if self.stage then root:showPreview(self.stage) end
end

function Phone:showLatestTurn()
	local refs = self.conversationRefs
	if self:conversationOpen() and refs and refs.transcriptScroll then refs.transcriptScroll:scrollTo("bottom", false) end
end

function Phone:openConversation()
	if self:conversationOpen() then return true end
	local root, ns = self.root, self.ns
	if not root.model then root:showNewProject(); return nil end
	ns.presentSheet(function()
		local native, refs = xml.renderFile(VIEWS .. "sheets/ConversationShell.etlua", self:shellData(), ns)
		self.navigation = refs.conversationNav
		self.conversation = Template.new(refs.content, VIEWS .. "sheets/Conversation.etlua", ns)
		local _, contentRefs = self.conversation:update(self:conversationData())
		self.conversationRefs = contentRefs
		return native
	end, { detents = SHEET.detents, largestUndimmedDetent = SHEET.largestUndimmedDetent, dragIndicator = SHEET.dragIndicator,
		onDismiss = DataModel.bound(root.store, function() self:conversationClosed() end) })
	self:showLatestTurn()
	return true
end

-- The sheet is gone, by Done or by a drag: dictation into a composer nobody
-- sees stops with it, and the capsule takes over.
function Phone:conversationClosed()
	self.root.chat:stopDictation()
	self.conversation, self.conversationRefs, self.navigation, self.editor, self.codePage = nil, nil, nil, nil, nil
	self.root:render()
end

function Phone:closeConversation()
	if not self:conversationOpen() then return end
	self.ns.dismiss()
	self:conversationClosed()
end

function Phone:showCode()
	if self.editor and not self.editor.closed then return end
	if not self:openConversation() then return end
	local ns = self.ns
	self.codePage = ns.pushScreen(self.navigation, nil, function()
		local page, refs = xml.renderFile(VIEWS .. "pages/Code.etlua", { project = self.root.activeProject, actions = self.root.actions }, ns)
		self.editor = Template.new(refs.editorHost, VIEWS .. "sections/Editor.etlua", ns)
		self.editor:update(self:editorData())
		return page
	end)
end

function Phone:codeClosed()
	self.editor, self.codePage = nil, nil
end

-- The microphone on the capsule: the conversation opens and listens.
function Phone:dictate()
	if not self:openConversation() then return end
	local ok, err = self.root.chat:toggleDictation()
	if not ok and err then self.root.status = err; self.root:render() end
end

-- The phone's actions join the root's table. Files resolve by name, so a
-- file the agent adds has a menu action at once.
function Phone:extendActions(actions, bound)
	local root = self.root
	actions.openConversation = bound(function() return self:openConversation() end)
	actions.closeConversation = bound(function() self:closeConversation() end)
	actions.showCode = bound(function() self:showCode() end)
	actions.codeClosed = bound(function() self:codeClosed() end)
	actions.dictate = bound(function() self:dictate() end)
	setmetatable(actions, { __index = function(_, name)
		local file = name:match("^selectFile_(.+)$")
		if file then return bound(function() root:selectFile(file) end) end
	end })
end

return Phone
