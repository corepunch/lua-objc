local CompassGesture = require("apps.adventure-arena.services.CompassGesture")

local Controller = {}
Controller.__index = Controller

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "session model is required"),
		findGame = assert(options.findGame, "adventure lookup callback is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		ns = assert(options.ns, "native platform module is required"),
		readingSettings = assert(options.readingSettings, "reading settings model is required"),
		renderTemplate = assert(options.renderTemplate, "template renderer is required"),
		presentSheet = assert(options.presentSheet, "sheet presenter is required"),
		dismissSheet = assert(options.dismissSheet, "sheet dismisser is required"),
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
		inputChanged = function(text) self:updateComposer(text) end,
		inputCommand = function(command)
			if command ~= "submit" then return false end
			self:submitCommand(self.refs.input.text)
			return true
		end,
		look = function() self:submitCommand("look") end,
		inventory = function() self:submitCommand("inventory") end,
		dictate = function() self:toggleDictation() end,
		close = function() self:close() end,
		readingSettings = function() self:showReadingSettings() end,
		compassDrag = function(gesture)
			if type(gesture) ~= "table" or not self.refs then return end
			local coordinateSpace = self.ns.platform == "AppKit" and "bottom-left" or "top-left"
			if gesture.state == "changed" or gesture.state == "began" then
				if self.ns.platform == "UIKit" then
					local x, y = CompassGesture.offset(gesture.translation, coordinateSpace)
					self.refs.compassImage.offsetX = x
					self.refs.compassImage.offsetY = y
				end
				return
			end
			if self.ns.platform == "UIKit" then
				self.refs.compassImage.offsetX = 0
				self.refs.compassImage.offsetY = 0
			end
			if gesture.state ~= "ended" then return end
			local direction = CompassGesture.direction(gesture.translation, coordinateSpace)
			if direction and self.model:hasExit(direction) then
				self:submitCommand("go " .. direction)
			end
		end,
	}
	local presentation = self.model:presentation()
	presentation.speechAvailable = speechAvailable
	presentation.actions = actions
	self.view, self.refs = self.push("Session", presentation, game.title)
	self.refs.input.accessibilityLabel = "Command"
	self:applyReadingSettings()
	self:updateComposer(self.refs.input.text)
	return true
end

function Controller:updateComposer(text)
	if not self.refs then return end
	local hasText = type(text) == "string" and text:find("%S") ~= nil
	local showSend = not self.refs.dictate or (hasText and not self.dictationActive)
	self.refs.send.hidden = not showSend
	self.refs.send.enabled = hasText
	if self.refs.dictate then self.refs.dictate.hidden = showSend end
	self.view:layout()
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
	self:updateComposer(self.refs.input.text)
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
	self:updateComposer(self.refs.input.text)
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
	if type(command) ~= "string" or not command:find("%S") then return false end
	self:cancelDictation()
	local ok, err = self.model:submit(command)
	local presentation = self.model:presentation()
	self.refs.roomTitle.text = presentation.roomTitle
	self.refs.output.text = presentation.transcript
	self.refs.progress.text = presentation.progress
	self.refs.input.text = ""
	self.refs.dictationStatus.text = ""
	self:updateComposer("")
	return ok, err
end

function Controller:showReadingSettings()
	local data = self.readingSettings:presentation()
	data.actions = {
		fontChanged = function(index)
			if self.readingSettings:setFontIndex(index) then self:updateReadingSettings() end
		end,
		sizeChanged = function(value)
			if self.readingSettings:setFontSize(value) then self:updateReadingSettings() end
		end,
		decreaseSize = function()
			self.readingSettings:adjustFontSize(-1)
			self:updateReadingSettings()
		end,
		increaseSize = function()
			self.readingSettings:adjustFontSize(1)
			self:updateReadingSettings()
		end,
		themeChanged = function(index)
			if self.readingSettings:setThemeIndex(index) then self:updateReadingSettings() end
		end,
		done = function() self:closeReadingSettings() end,
	}
	local sheet, refs = self.renderTemplate("ReadingSettings", data)
	self.readingSettingsRefs = refs
	self.readingSettingsSheet = self.presentSheet(sheet, { "medium", "large" })
	self:updateReadingSettings()
	return true
end

function Controller:updateReadingSettings()
	self:applyReadingSettings()
	local refs = self.readingSettingsRefs
	if not refs then return end
	local settings = self.readingSettings:presentation()
	if self.ns.platform == "UIKit" then
		refs.sizeSlider.value = settings.fontSize
	else
		refs.sizeSlider.doubleValue = settings.fontSize
	end
	refs.sizeValue.text = tostring(settings.fontSize)
	refs.preview.backgroundColor = self.ns._systemColor(settings.backgroundColor)
	refs.previewTitle.font = self.ns._font(settings.fontSize + 3, "bold", false, settings.font)
	refs.previewTitle.textColor = self.ns._systemColor(settings.primaryTextColor)
	refs.previewBody.font = self.ns._font(settings.fontSize, nil, false, settings.font)
	refs.previewBody.textColor = self.ns._systemColor(settings.primaryTextColor)
end

function Controller:applyReadingSettings()
	if not self.refs then return end
	local settings = self.readingSettings:presentation()
	local background = self.ns._systemColor(settings.backgroundColor)
	local primary = self.ns._systemColor(settings.primaryTextColor)
	local secondary = self.ns._systemColor(settings.secondaryTextColor)
	self.view.backgroundColor = background
	self.refs.transcriptScroll.backgroundColor = background
	self.refs.output.font = self.ns._font(settings.fontSize, nil, false, settings.font)
	self.refs.output.textColor = primary
	self.refs.gameTitle.font = self.ns._font(settings.fontSize + 3, "bold", false, settings.font)
	self.refs.gameTitle.textColor = primary
	self.refs.gameDescription.font = self.ns._font(settings.fontSize, nil, false, settings.font)
	self.refs.gameDescription.textColor = primary
	self.refs.roomTitle.font = self.ns._font(settings.fontSize + 3, "bold", false, settings.font)
	self.refs.roomTitle.textColor = primary
	self.refs.progress.textColor = secondary
	self.refs.dictationStatus.textColor = secondary
	self.refs.input.font = self.ns._font(math.max(15, math.min(settings.fontSize, 20)), nil, false, settings.font)
	self.refs.input.textColor = primary
	if self.ns.platform == "UIKit" then
		self.view.overrideUserInterfaceStyle = settings.appearance
	end
end

function Controller:closeReadingSettings()
	self.dismissSheet(self.readingSettingsSheet)
	self.readingSettingsSheet, self.readingSettingsRefs = nil, nil
end

return Controller
