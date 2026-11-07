local Model = require("apps.studio.helpers.Chat")
local Agent = require("apps.studio.services.Agent")
local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({ model = Model, draft = "" }, Controller)
end

function Controller:attach(session, device, preview, changed)
	self:stop()
	self.session, self.device, self.changed = session, device, changed
	self.draft, self.attachments = "", {}
	self.agent = Agent.new(session, device.transport, device.json, preview, changed)
end

function Controller:presentation(conversation, code)
	if not conversation and self.session then
		conversation = { messages = self.session.workspace.messages, modelId = self.session.workspace.modelId,
			draft = self.draft, busy = self.agent.busy, listening = self.listening, attachments = self.attachments }
	end
	return self.model.presentation(conversation, code)
end

function Controller:send()
	if not self.session then return nil, "Open a project first" end
	if not self.draft:match("%S") then return nil, "Enter a message" end
	local key = self.device.credentials.read()
	if not key or key == "" then return nil, "Add your OpenRouter API key in Settings", "credentials" end
	local ok, err = self.session:saveDrafts()
	if not ok then return nil, err end
	local draft, attachments = self.draft, self.attachments
	self.draft, self.attachments = "", {}
	if self.speech then self.speech:cancel(); self.listening = false end
	ok, err = self.agent:send(draft, key, attachments)
	if not ok then self.draft, self.attachments = draft, attachments end
	return ok, err
end

function Controller:stopDictation()
	self.listening = false
	if self.speech then self.speech:cancel() end
end

function Controller:stop()
	if self.agent then self.agent:stop() end
	self:stopDictation()
end

function Controller:newConversation()
	self:stop()
	if self.session then self.session.workspace:clearConversation() end
	self.draft = ""
	if self.changed then self.changed() end
end

function Controller:attachFiles(files)
	if self.agent.busy then return nil, "Wait for the agent to finish" end
	if #self.attachments + #files > 4 then return nil, "Attach up to four text files" end
	for _, file in ipairs(files) do
		if type(file.name) ~= "string" or type(file.text) ~= "string" or #file.text > 128 * 1024 then
			return nil, "Attachments must be UTF-8 text under 128 KB"
		end
	end
	for _, file in ipairs(files) do table.insert(self.attachments, file) end
	self.changed()
	return true
end

function Controller:toggleDictation()
	if self.agent.busy then return end
	if self.listening then self.speech:stop(); return end
	if not self.device.speech then return nil, "Dictation is unavailable" end
	self.dictationPrefix, self.listening = self.draft, true
	if not self.speech then
		self.speech = self.device.speech.recognizer(function(state, text, message)
			if state == "partial" or state == "finished" then
				local prefix = self.dictationPrefix or ""
				self.draft = prefix .. (prefix ~= "" and " " or "") .. (text or "")
			end
			if state == "finished" or state == "idle" or state == "error" then self.listening = false end
			if state == "error" then self.session.workspace:message("error", message or "Dictation failed") end
			self.changed()
		end)
	end
	self.speech:start()
	self.changed()
	return true
end
return Controller
