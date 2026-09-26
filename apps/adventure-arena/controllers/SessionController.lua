local CompassGesture = require("apps.adventure-arena.services.CompassGesture")

local Controller = {}
Controller.__index = Controller

-- How long the "+5 points" glass capsule stays over the page.
local TOAST = { seconds = 2.2 }

function Controller.new(options)
	return setmetatable({
		model = assert(options.model, "session model is required"),
		findGame = assert(options.findGame, "adventure lookup callback is required"),
		push = assert(options.push, "navigation push callback is required"),
		back = assert(options.back, "navigation back callback is required"),
		ns = assert(options.ns, "native platform module is required"),
		readingSettings = assert(options.readingSettings, "reading settings model is required"),
		readingOptions = options.readingOptions,
		savedGames = options.savedGames,
		renderTemplate = assert(options.renderTemplate, "template renderer is required"),
		mountTemplate = assert(options.mountTemplate, "template mount is required"),
		presentSheet = assert(options.presentSheet, "sheet presenter is required"),
		dismissSheet = assert(options.dismissSheet, "sheet dismisser is required"),
		-- Moments: a haptic and a toast when the score changes.
		haptics = options.haptics,
		after = options.after or function() end,
		onProgress = options.onProgress or function() end,
		speech = nil,
		dictationActive = false,
		dictationPrefix = "",
	}, Controller)
end

-- Opens a story at its last page when it has an autosave, or from its title
-- page when `fresh` is set or nothing is saved.
function Controller:show(id, fresh)
	local game = self.findGame(id)
	if not game then return false end
	local saved = not fresh and self.savedGames and self.savedGames:find(id) or nil
	local ok, err = self.model:start(game, saved)
	if not ok then
		self.push("SessionError", {
			title = game.title, message = err, actions = { back = self.back },
		})
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
		inputFocused = function() self:scrollTranscript(true) end,
		look = function() self:submitCommand("look") end,
		inventory = function() self:submitCommand("inventory") end,
		dictate = function() self:toggleDictation() end,
		close = function() self:close() end,
		readingSettings = function() self:showReadingSettings() end,
		compassDrag = function(gesture)
			if type(gesture) ~= "table" or not self.refs then return end
			local direction = CompassGesture.direction(gesture.translation)
			if gesture.state == "changed" or gesture.state == "began" then
				local x, y = CompassGesture.offset(gesture.translation)
				self.refs.compassImage.offsetX = x
				self.refs.compassImage.offsetY = y
				self:updateCompass(direction)
				return
			end
			self.refs.compassImage.offsetX = 0
			self.refs.compassImage.offsetY = 0
			self:updateCompass(nil)
			if gesture.state ~= "ended" then return end
			if direction and self.model:hasExit(direction) then
				self:submitCommand("go " .. direction)
			end
		end,
	}
	local presentation = self.model:presentation()
	presentation.speechAvailable = speechAvailable
	presentation.compassSegments = CompassGesture.segments()
	actions.disappear = function() self:onDisappear() end
	presentation.actions = actions
	self.page, self.refs = self.push("Session", presentation)
	self.transcript = self.mountTemplate(self.refs.transcript, "Transcript")
	self.suggestions = self.mountTemplate(self.refs.suggestions, "Suggestions")
	self:applyReadingSettings()
	self:updateComposer(self.refs.input.text)
	self:updateCompass(nil)
	self:scrollTranscript(false)
	self.onProgress()
	return true
end

function Controller:isOpen()
	return self.refs ~= nil
end

function Controller:scrollTranscript(animated)
	local scroll = self.refs and self.refs.transcriptScroll
	if not scroll then return end
	scroll:scrollTo("bottom", animated == true)
end

function Controller:updateCompass(activeDirection)
	if not self.refs then return end
	for _, segment in ipairs(CompassGesture.segments()) do
		local exitArc = self.refs["compassExit_" .. segment.direction]
		local dragArc = self.refs["compassDrag_" .. segment.direction]
		local available = self.model:hasExit(segment.direction)
		if exitArc then exitArc.strokeAlpha = available and 1 or 0 end
		if dragArc then
			local active = activeDirection == segment.direction
			dragArc.strokeAlpha = active and 1 or 0
			if active then dragArc.stroke = available and "accent" or "tertiary" end
		end
	end
end

function Controller:updateComposer(text)
	if not self.refs then return end
	local hasText = type(text) == "string" and text:find("%S") ~= nil
	local showSend = not self.refs.dictate or (hasText and not self.dictationActive)
	self.refs.send.hidden = not showSend
	self.refs.send.enabled = hasText
	if self.refs.dictate then self.refs.dictate.hidden = showSend end
	self:renderSuggestions(text)
end

-- Suggestions follow every keystroke. A whole command ("north", "open
-- mailbox") runs on tap; a completion replaces the composer text so the
-- player can keep typing.
function Controller:renderSuggestions(text)
	if not self.suggestions or self.suggestions:isDisposed() then return end
	local suggestions = self.model:suggestions(type(text) == "string" and text or "")
	local actions = {}
	for index, suggestion in ipairs(suggestions) do
		actions["suggest_" .. index] = function() self:applySuggestion(suggestion) end
	end
	self.currentSuggestions = suggestions
	self.suggestions:update({ suggestions = suggestions, actions = actions })
	self.refs.suggestionScroll.hidden = #suggestions == 0
end

function Controller:applySuggestion(suggestion)
	if not self.refs or type(suggestion) ~= "table" then return false end
	if suggestion.submit then return self:submitCommand(suggestion.text) end
	self.refs.input.text = suggestion.text
	self:updateComposer(suggestion.text)
	return true
end

function Controller:renderTranscript()
	if not self.transcript or self.transcript:isDisposed() then return end
	local data = self.model:presentation()
	local settings = self.readingSettings:presentation()
	data.reading = {
		font = settings.font, fontSize = settings.fontSize, lineSpacing = settings.lineSpacing,
		alignment = settings.alignment, primary = settings.primaryTextColor,
		secondary = settings.secondaryTextColor, rule = settings.ruleColor,
	}
	data.actions = {}
	return self.transcript:update(data)
end

function Controller:onSpeechEvent(state, text, message)
	if not self.refs then return end
	self.refs.dictationStatus.hidden = state == "idle" or state == "finished"
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
	if self.transcript then self.transcript:dispose() end
	if self.suggestions then self.suggestions:dispose() end
	self.speech = nil
	self.refs = nil
	self.page = nil
	self.transcript, self.suggestions, self.currentSuggestions = nil, nil, nil
	self.onProgress()
end

function Controller:submitCommand(command)
	if type(command) ~= "string" or not command:find("%S") then return false end
	self:cancelDictation()
	local ok, err = self.model:submit(command)
	local presentation = self.model:presentation()
	self.refs.progress.text = presentation.progress
	self.refs.sessionPlace.text = presentation.chapterLabel ~= ""
		and (presentation.chapterLabel .. " · " .. presentation.roomTitle) or presentation.roomTitle
	self.refs.input.text = ""
	self.refs.dictationStatus.text = ""
	self.refs.dictationStatus.hidden = true
	self:renderTranscript()
	self:updateCompass(nil)
	self:scrollTranscript(true)
	self:updateComposer("")
	self:announceScore(presentation.scoreChange)
	if self.savedGames then self.savedGames:record(self.model:snapshot()) end
	self.onProgress()
	return ok, err
end

-- Points are a moment: a success haptic and a glass capsule over the page
-- that fades after a beat, as Game Center achievements announce themselves.
function Controller:announceScore(change)
	if not self.refs or type(change) ~= "number" or change == 0 then return end
	local points = math.abs(change) == 1 and "point" or "points"
	self.refs.scoreToastText.text = string.format("%s%d %s", change > 0 and "+" or "−", math.abs(change), points)
	self.refs.scoreToast.hidden = false
	if self.haptics then
		if change > 0 then self.haptics.notification("success") else self.haptics.notification("warning") end
	end
	self.toastGeneration = (self.toastGeneration or 0) + 1
	local generation = self.toastGeneration
	self.after(TOAST.seconds, function()
		if self.refs and self.toastGeneration == generation then self.refs.scoreToast.hidden = true end
	end)
end

function Controller:showReadingSettings()
	local sheet, refs = self.renderTemplate("ReadingSettings", {
		actions = { done = function() self:closeReadingSettings() end },
	})
	self.readingSettingsRefs = refs
	if self.readingOptions then
		self.readingSettingsOptions = self.readingOptions:mount(refs.readingOptions, false)
	end
	self.readingSettingsSheet = self.presentSheet(sheet, { "medium", "large" })
	return true
end

-- Page colour, ink, face, size and leading belong to the transcript's
-- description, so a change re-renders the page rather than restyling labels.
function Controller:applyReadingSettings()
	if not self.refs then return end
	local settings = self.readingSettings:presentation()
	self.refs.session.backgroundColor = self.ns.Color(settings.pageColor)
	self.refs.progress.textColor = self.ns.Color(settings.secondaryTextColor)
	self.refs.dictationStatus.textColor = self.ns.Color(settings.secondaryTextColor)
	self.refs.input.font = self.ns.Font { size = math.max(15, math.min(settings.fontSize, 20)), design = settings.font }
	self.refs.input.textColor = self.ns.Color(settings.primaryTextColor)
	if self.ns.platform == "UIKit" then
		-- A Night page is dark whatever the system says: the page, its view
		-- controller (so the status bar turns light) and the running head
		-- in the navigation bar all take the page's appearance.
		self.refs.session.overrideUserInterfaceStyle = settings.appearance
		if self.page then self.page.overrideUserInterfaceStyle = settings.appearance end
		self.refs.sessionTitle.overrideUserInterfaceStyle = settings.appearance
		self.refs.sessionPlace.overrideUserInterfaceStyle = settings.appearance
	end
	self:renderTranscript()
end

function Controller:closeReadingSettings()
	if self.readingOptions and self.readingSettingsOptions then
		self.readingOptions:unmount(self.readingSettingsOptions)
	end
	self.dismissSheet(self.readingSettingsSheet)
	self.readingSettingsSheet, self.readingSettingsRefs, self.readingSettingsOptions = nil, nil, nil
end

return Controller
