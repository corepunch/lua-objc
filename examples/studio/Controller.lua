local Model = require("examples.studio.Model")
local Agent = require("examples.studio.services.Agent")
local Preview = require("examples.studio.services.Preview")
local Device = require("examples.studio.services.Device")
local Controller = {}
Controller.__index = Controller
local VIEWS = "examples/studio/views/"
local SEED = { "init.lua", "Model.lua", "Controller.lua", "views/Window.etlua" }
function Controller.new()
	return setmetatable({}, Controller)
end
function Controller:createWindow()
	self.ns = require("ns")
	local ns = self.ns
	assert(ns.Preview, "Lua Studio requires the iPad runtime. Use make ipad-run.")
	self.xml = require("ui.xml")
	local device, seed = Device.new(ns), {}
	for _, name in ipairs(SEED) do
		local path = "examples/playground/" .. name
		seed[path] = assert(ns._readFile(path))
	end
	self.model = Model.new(device.storage, seed)
	self.preview = Preview.new(ns, ns._readFile)
	self.agent = Agent.new(self.model, device.transport, device.json,
		function() return self:reloadPreview() end, function() self:update() end)
	self.model:message("Agent", "What would you like to build? I can edit this app and show the changes here. Start with OpenRouter Free in Settings, or add your API key to use a stronger model.")
	local config, refs = self.xml.renderFile(VIEWS .. "Window.etlua", {
		actions = {
			send = function() self:send() end,
			stop = function() self.agent:stop(); self:setStatus("Stopped") end,
			undo = function() self:undo() end,
			reload = function() self:reloadPreview() end,
			files = function() self:showFiles() end,
			settings = function() self:showSettings() end,
			voice = function() self:voice() end,
		},
	}, ns)
	self.refs = refs
	local window = ns.Window(config)
	self:reloadPreview()
	self:update()
	return window
end
function Controller:setStatus(text)
	self.status = text
	self.refs.status.text = text
end
function Controller:update()
	if not self.refs then return end
	self.refs.transcript.text = self.model:transcript()
	self.refs.send.enabled = not self.agent.busy
	self.refs.stop.enabled = self.agent.busy == true
	self.refs.undo.enabled = not self.agent.busy and #self.model.history > 0
	self.refs.files.enabled = not self.agent.busy
	self.refs.settings.enabled = not self.agent.busy
	self.refs.status.text = self.agent.busy and "Agent is working…" or (self.status or "Ready")
end
function Controller:reloadPreview()
	local controller, err = self.preview:render(self.model.files)
	if controller then
		self.refs.preview.content = controller
		self.previewLoads = (self.previewLoads or 0) + 1
		self:setStatus("Preview ready · revision " .. self.model.revision .. " · load " .. self.previewLoads)
	else
		self:setStatus("Preview error · previous version is still visible")
		self.model:message("Preview error", tostring(err))
	end
	self:update()
	return controller ~= nil, err
end
function Controller:send()
	local text = self.refs.composer.text
	local read, key = pcall(self.ns._credential, "openrouter")
	if not read then
		self:setStatus("Cannot read API key: " .. tostring(key))
		self:showSettings()
		return
	end
	if not key or key == "" then
		self:setStatus("Add an OpenRouter API key in Settings before sending")
		self:showSettings()
		return
	end
	local ok, err = self.agent:send(text, key)
	if ok then self.refs.composer.text = "" else self:setStatus(err) end
end
function Controller:undo()
	if self.agent.busy then return end
	local ok, err = self.model:undo()
	if ok then self:reloadPreview() else self:setStatus(err) end
end
function Controller:voice()
	-- System keyboard dictation supports the user's configured languages and microphone privacy settings.
	self.ns._focus(self.refs.composer)
	self:setStatus("Use the microphone on the keyboard to dictate, then tap Send")
end
function Controller:showSettings()
	local refs
	local view
	view, refs = self.xml.renderFile(VIEWS .. "Settings.etlua", {
		model = self.model.model,
		actions = { save = function()
			local ok, err = self.model:setModel(refs.model.text)
			if not ok then refs.status.text = err; return end
			local saved, keyError = pcall(self.ns._credential, "openrouter", refs.key.text)
			if not saved then refs.status.text = tostring(keyError); return end
			self.ns.dismiss()
			self:setStatus("OpenRouter settings saved")
		end, free = function()
			refs.model.text = "openrouter/free"
			refs.status.text = "Free router selected · an OpenRouter key is still required"
		end },
	}, self.ns)
	local read, key = pcall(self.ns._credential, "openrouter")
	if read then refs.key.text = key or ""
	else refs.status.text = "Cannot read API key: " .. tostring(key) end
	for _, field in ipairs({ refs.key, refs.model }) do
		field.verbatim = true
	end
	self.ns.presentSheet(view, { title = "OpenRouter", detents = { "large" } })
end
function Controller:showFiles()
	local refs
	local selected = "examples/playground/views/Window.etlua"
	local function open()
		local path = refs.path.text
		if not Model.validPath(path) then refs.status.text = "Use a path inside examples/playground/"; return end
		selected = path
		refs.editor.text = self.model.files[path] or ""
		refs.status.text = self.model.files[path] and "File loaded" or "New file · Save to create"
	end
	local view
	view, refs = self.xml.renderFile(VIEWS .. "Files.etlua", {
		path = selected, source = self.model.files[selected], paths = self.model:listFiles(),
		actions = { open = open, save = function()
			if refs.path.text ~= selected then refs.status.text = "Tap Open before editing another file"; return end
			local ok, err = self.model:apply({ { path = selected, content = refs.editor.text } })
			if not ok then refs.status.text = err; return end
			self:reloadPreview()
			refs.status.text = "Saved · revision " .. self.model.revision
		end },
	}, self.ns)
	refs.editor.verbatim = true
	refs.path.verbatim = true
	self.ns.presentSheet(view, { title = "Project files", detents = { "large" } })
end
return Controller
