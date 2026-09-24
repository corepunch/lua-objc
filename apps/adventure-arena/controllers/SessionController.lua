local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "session model is required"),
		findGame = assert(options.findGame, "adventure lookup callback is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		ns = assert(options.ns, "native platform module is required"),
		speech = nil,
		dictationActive = false,
		dictationPrefix = "",
	}, Controller)
end

function Controller:show(id)
	local game = self.findGame(id)
	if not game then return false end
	local ok, err = self.model:start(game)
	if not ok then
		self.push("SessionError", {
			message = err, actions = { back = self.back },
		}, game.title)
		return false
	end
	self:cancelDictation()
	local speechAvailable = type(self.ns.SpeechRecognizer) == "function"
	if speechAvailable then
		self.speech = self.ns.SpeechRecognizer(function(state, text, message)
			self:onSpeechEvent(state, text, message)
		end)
	end
	local actions = {
		submit = function() self:submitCommand(self.refs.input.text) end,
		look = function() self:submitCommand("look") end,
		inventory = function() self:submitCommand("inventory") end,
		dictate = function() self:toggleDictation() end,
		close = function() self:close() end,
	}
	self.view, self.refs = self.push("Session", {
		transcript = self.model:transcript(),
		speechAvailable = speechAvailable,
		actions = actions,
	}, game.title)
	self.refs.input.accessibilityLabel = "Command"
	self.ns._textFieldCallbacks(self.refs.input, nil, function(command)
		if command ~= "submit" then return false end
		actions.submit()
		return true
	end)
	return true
end

function Controller:onSpeechEvent(state, text, message)
	if not self.refs then return end
	if state == "listening" then
		self.dictationActive = true
		self.refs.dictationStatus.text = "Listening… Tap the microphone to finish."
	elseif state == "partial" or state == "finished" then
		local separator = self.dictationPrefix ~= ""
			and not self.dictationPrefix:match("%s$") and " " or ""
		self.refs.input.text = self.dictationPrefix .. separator .. (text or "")
		if state == "finished" then
			self.dictationActive = false
			self.refs.dictationStatus.text = ""
		end
	elseif state == "starting" then
		self.refs.dictationStatus.text = "Waiting for microphone access…"
	elseif state == "processing" then
		self.refs.dictationStatus.text = "Transcribing…"
	elseif state == "error" then
		self.dictationActive = false
		self.refs.dictationStatus.text = message or "Dictation is unavailable. Check microphone and speech access in Settings."
	elseif state == "idle" then
		self.dictationActive = false
		self.refs.dictationStatus.text = ""
	end
	self.view:layout()
end

function Controller:toggleDictation()
	if not self.speech then return end
	if self.dictationActive then
		self.speech:stop()
		self.refs.dictationStatus.text = "Transcribing…"
	else
		self.dictationPrefix = self.refs.input.text or ""
		self.dictationActive = true
		self.speech:start()
	end
	self.view:layout()
end

function Controller:cancelDictation()
	if self.speech and self.dictationActive then self.speech:cancel() end
	self.dictationActive = false
end

function Controller:close()
	self:onDisappear()
	self.back()
end

function Controller:onDisappear()
	self:cancelDictation()
	self.speech = nil
	self.refs = nil
	self.view = nil
end

function Controller:submitCommand(command)
	self:cancelDictation()
	local ok, err = self.model:submit(command)
	self.refs.output.text = self.model:transcript()
	self.refs.input.text = ""
	self.refs.dictationStatus.text = ""
	self.view:layout()
	return ok, err
end

return Controller
